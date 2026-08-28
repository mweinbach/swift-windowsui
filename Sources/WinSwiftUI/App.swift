import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import SwiftWindowsUI

// MARK: - Timer State Observability

/// Immutable snapshot of animation timer state for observability.
/// Captures the configuration determined by `syncAnimationDriver`.

// MARK: - WidgetKit shims

@MainActor
public protocol Scene {
    associatedtype Body: Scene

    @SceneBuilder
    var body: Body { get }

    func makeWindowConfiguration() -> WindowGroupConfiguration
    func makeWindowConfigurations() -> [WindowGroupConfiguration]
}
extension Scene {
    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        body.makeWindowConfiguration()
    }

    /// Preserves every scene declared by a custom scene body. Primitive
    /// scenes retain the existing single-configuration implementation.
    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        if Body.self == Never.self {
            return [makeWindowConfiguration()]
        }
        return body.makeWindowConfigurations()
    }
}
extension Never: Scene {
    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        fatalError("Never cannot build a window configuration")
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        fatalError("Never cannot build window configurations")
    }
}

/// The ordered scene declarations produced by a multi-scene app body.
/// Configuration collection does not create native windows; the coordinator
/// opens the primary window at launch and settings or secondary windows only
/// when their corresponding scene action is invoked.
@MainActor
public struct SceneCollection: Scene {
    public typealias Body = Never

    private let configurations: [WindowGroupConfiguration]

    init(configurations: [WindowGroupConfiguration]) {
        self.configurations = configurations
    }

    public var body: Never {
        fatalError("SceneCollection has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        guard let configuration = configurations.first else {
            preconditionFailure("An empty scene collection has no single window configuration")
        }
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        configurations
    }
}

/// Marks scene content produced by an availability check. The marker keeps
/// ordinary boolean branches out of SceneBuilder, matching SwiftUI's scene
/// declaration syntax rather than the broader syntax of ViewBuilder.
public protocol _LimitedAvailabilitySceneMarker {}

@MainActor
private struct LimitedAvailabilityScene: Scene, _LimitedAvailabilitySceneMarker {
    let body: SceneCollection
}

/// Builds ordinary SwiftUI-shaped app and scene declarations, including
/// multiple scenes and `if #available` declarations without an else branch.
@resultBuilder
@MainActor
public enum SceneBuilder {
    public static func buildExpression<Content: Scene>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock() -> SceneCollection {
        SceneCollection(configurations: [])
    }

    public static func buildBlock<Content: Scene>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<each Content: Scene>(
        _ content: repeat each Content
    ) -> SceneCollection {
        var configurations: [WindowGroupConfiguration] = []
        for scene in repeat each content {
            configurations.append(contentsOf: scene.makeWindowConfigurations())
        }
        return SceneCollection(configurations: configurations)
    }

    /// SwiftUI supports availability conditions here, not arbitrary boolean
    /// conditions, else branches, or loops. Only buildLimitedAvailability
    /// supplies the marker needed by this optional entry point.
    public static func buildOptional(
        _ content: (any Scene & _LimitedAvailabilitySceneMarker)?
    ) -> SceneCollection {
        SceneCollection(configurations: content?.makeWindowConfigurations() ?? [])
    }

    public static func buildLimitedAvailability<Content: Scene>(
        _ content: Content
    ) -> any Scene & _LimitedAvailabilitySceneMarker {
        LimitedAvailabilityScene(body: SceneCollection(configurations: content.makeWindowConfigurations()))
    }
}
@MainActor
public protocol App {
    associatedtype Body: Scene

    init()

    @SceneBuilder
    var body: Body { get }

    /// Override to inject a custom render backend factory.
    ///
    /// The default names no GPU backend, so the WinSwiftUI facade stays
    /// renderer-neutral (Phase 8 modularization). The Windows product pins the
    /// D3D11 GPU factory at its composition root — the `swift-windowsui`
    /// executable overrides this requirement with the concrete factory from
    /// the renderer backend target.
    static func renderBackendFactory() -> RenderBackendFactory

    /// Override to inject the factory responsible for native window creation
    /// and the application event loop, independently of renderer selection.
    ///
    /// The current retained window host still requires a `Win32Window`; an
    /// incompatible factory fails explicitly instead of pretending that the
    /// rest of the application is already platform-portable.
    static func platformHostFactory() -> any PlatformHostFactory
}
extension App {
    /// The software presenter, not ``CPURenderBackendFactory``: an app that
    /// never overrides this still opens a window that shows something. The CPU
    /// reference backend rasterizes into `lastRenderedBitmap` and never blits,
    /// so it is the snapshot and parity backend, never a window's presenter.
    public static func renderBackendFactory() -> RenderBackendFactory {
        SoftwareWindowRenderBackendFactory()
    }

    /// The current shipping platform implementation. Applications may
    /// override this separately from their graphics backend factory.
    public static func platformHostFactory() -> any PlatformHostFactory {
        Win32PlatformHostFactory()
    }

    public static func main() {
        let app = Self.init()
        let resolved = RenderBackendFactoryResolution.resolve(Self.renderBackendFactory())

        do {
            let coordinator = WinSwiftUIWindowCoordinator(
                sceneConfigurations: app.body.makeWindowConfigurations(),
                renderBackendFactory: resolved.factory,
                backendResolution: resolved.resolution,
                platformHostFactory: Self.platformHostFactory(),
                // `--diagnostics`: open the real window, drive it, measure it,
                // write the report and close. Wired at the composition root
                // rather than behind a build flag, because the session worth
                // measuring is the one the product actually ships.
                liveDiagnostics: LiveDiagnosticsConfiguration.fromCommandLine()
            )
            _ = try coordinator.run()
        } catch {
            print("Failed to start WinSwiftUI app: \(error)")
        }
    }
}
@MainActor
public struct WindowGroup: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration

    public init(
        _ title: String = "WinSwiftUI",
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        @ViewBuilder content: @escaping @MainActor () -> [AnyView]
    ) {
        var configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: content()
        )
        configuration.windowContentFactory = content
        self.configuration = configuration
    }

    public init(
        _ title: String = "WinSwiftUI",
        id: String,
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        @ViewBuilder content: @escaping @MainActor () -> [AnyView]
    ) {
        var configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: content(),
            windowID: id
        )
        configuration.windowContentFactory = content
        self.configuration = configuration
    }

    public init<Content: View, Value: Codable & Hashable>(
        _ title: String = "WinSwiftUI",
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        for valueType: Value.Type,
        @ViewBuilder content: @escaping (Binding<Value>) -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: [],
            forType: Value.self,
            dataBoundContent: { anyValue in
                guard let value = anyValue.base as? Value else { return [] }
                let binding = Binding<Value>(get: { value }, set: { _ in })
                return [AnyView(content(binding))]
            }
        )
    }

    public init<Content: View, Value: Codable & Hashable>(
        _ title: String = "WinSwiftUI",
        id: String,
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        for valueType: Value.Type,
        @ViewBuilder content: @escaping (Binding<Value>) -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: [],
            windowID: id,
            forType: Value.self,
            dataBoundContent: { anyValue in
                guard let value = anyValue.base as? Value else { return [] }
                let binding = Binding<Value>(get: { value }, set: { _ in })
                return [AnyView(content(binding))]
            }
        )
    }

    public var body: Never {
        fatalError("WindowGroup has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}
@MainActor
public struct Window<Content: View>: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration

    public init(
        _ title: String,
        id: String? = nil,
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: [AnyView(content())],
            windowID: id
        )
    }

    public init(
        _ title: String,
        id: String? = nil,
        resizeToContents: Bool,
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: [AnyView(content())],
            windowID: id,
            resizeToContents: resizeToContents
        )
    }

    public init<Value: Codable & Hashable>(
        _ title: String,
        id: String? = nil,
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        for valueType: Value.Type,
        @ViewBuilder content: @escaping (Binding<Value>) -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: [],
            windowID: id,
            forType: Value.self,
            dataBoundContent: { anyValue in
                guard let value = anyValue.base as? Value else { return [] }
                let binding = Binding<Value>(get: { value }, set: { _ in })
                return [AnyView(content(binding))]
            }
        )
    }

    public var body: Never {
        fatalError("Window has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}
@MainActor
public struct WindowScene<Content: View>: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration

    public init(
        _ title: String,
        id: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())],
            windowID: id
        )
    }

    public init<Value: Codable & Hashable>(
        _ title: String,
        id: String? = nil,
        for valueType: Value.Type,
        @ViewBuilder content: @escaping (Binding<Value>) -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [],
            windowID: id,
            forType: Value.self,
            dataBoundContent: { anyValue in
                guard let value = anyValue.base as? Value else { return [] }
                let binding = Binding<Value>(get: { value }, set: { _ in })
                return [AnyView(content(binding))]
            }
        )
    }

    public var body: Never {
        fatalError("WindowScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}
@MainActor
public struct ImmersiveSpace<Content: View>: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration

    public init(
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: "ImmersiveSpace",
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())]
        )
    }

    public init(id: String, @ViewBuilder content: () -> Content) {
        self.configuration = WindowGroupConfiguration(
            title: id,
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())],
            windowID: id
        )
    }

    public var body: Never {
        fatalError("ImmersiveSpace has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}
@MainActor
public struct Volume<Content: View>: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration

    public init(
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: "Volume",
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())]
        )
    }

    public init(id: String, @ViewBuilder content: () -> Content) {
        self.configuration = WindowGroupConfiguration(
            title: id,
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())],
            windowID: id
        )
    }

    public var body: Never {
        fatalError("Volume has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}
@MainActor
public struct Settings<Content: View>: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration

    public init(
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = WindowGroupConfiguration(
            title: "Settings",
            size: IntSize(width: 600, height: 400),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())],
            isSettingsWindow: true
        )
    }

    public var body: Never {
        fatalError("Settings has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}
@MainActor
public struct DocumentGroup<Content: View>: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration

    public init<Document: FileDocument>(
        newDocument: @autoclosure @escaping () -> Document,
        @ViewBuilder content: @escaping (FileDocumentConfiguration<Document>) -> Content
    )
    where
        Document.ReadConfiguration == FileDocumentReadConfiguration,
        Document.WriteConfiguration == FileDocumentWriteConfiguration
    {
        self.configuration = Self.declaration(
            DocumentSceneDescriptor(
                documentType: Document.self, codec: .editable(Document.self),
                newDocument: { @MainActor in newDocument() }, isEditable: true,
                content: { [AnyView(content($0))] }
            )
        )
    }

    public init<Document: FileDocument>(
        viewing documentType: Document.Type,
        @ViewBuilder content: @escaping (FileDocumentConfiguration<Document>) -> Content
    ) where Document.ReadConfiguration == FileDocumentReadConfiguration {
        self.configuration = Self.declaration(
            DocumentSceneDescriptor(
                documentType: documentType, codec: .viewing(documentType),
                newDocument: nil, isEditable: false,
                content: { [AnyView(content($0))] }
            )
        )
    }

    public init<Document: FileDocument>(
        editing documentType: Document.Type,
        @ViewBuilder content: @escaping (FileDocumentConfiguration<Document>) -> Content
    )
    where
        Document.ReadConfiguration == FileDocumentReadConfiguration,
        Document.WriteConfiguration == FileDocumentWriteConfiguration
    {
        self.configuration = Self.declaration(
            DocumentSceneDescriptor(
                documentType: documentType, codec: .editable(documentType),
                newDocument: nil, isEditable: true,
                content: { [AnyView(content($0))] }
            )
        )
    }

    public init<Document: ReferenceFileDocument>(
        newDocument: @autoclosure @escaping () -> Document,
        @ViewBuilder content: @escaping (FileDocumentConfiguration<Document>) -> Content
    ) {
        // Retain the declaration shape without manufacturing a reference
        // model or pretending that value-inverse history supports it.
        self.configuration = Self.declaration(.unsupportedReferenceDocument)
    }

    private static func declaration(_ descriptor: DocumentSceneDescriptor) -> WindowGroupConfiguration {
        var configuration = WindowGroupConfiguration(
            title: "Untitled",
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [],
            isDocumentGroup: true
        )
        configuration.documentScene = descriptor
        return configuration
    }

    public var body: Never {
        fatalError("DocumentGroup has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}
public struct DocumentConfiguration: Sendable, Equatable {
    public init() {}
}
public struct DocumentTypes: Sendable, Equatable {
    public init() {}
}
public struct DocumentTypesConfiguration: Sendable, Equatable {
    public init() {}
}
public struct FileImporterConfiguration: Sendable, Equatable {
    public init() {}
}
public struct FileExporterConfiguration: Sendable, Equatable {
    public init() {}
}
public struct ContentTypes: Sendable, Equatable {
    public init() {}
}
public enum DropInteractionPhase: Sendable, Equatable {
    case entered
    case updated
    case exited
    case cancelled
}
@MainActor
public struct MenuBarExtra<Content: View>: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration
    private let isInserted: Binding<Bool>?

    public init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.isInserted = nil
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: IntSize(width: 400, height: 300),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())],
            isMenuBarExtra: true
        )
    }

    public init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.isInserted = nil
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: IntSize(width: 400, height: 300),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())],
            isMenuBarExtra: true
        )
    }

    public init(
        _ title: String,
        image: String,
        @ViewBuilder content: () -> Content
    ) {
        self.isInserted = nil
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: IntSize(width: 400, height: 300),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content())],
            isMenuBarExtra: true
        )
    }

    public init<Label: View>(
        isInserted: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.isInserted = isInserted
        self.configuration = WindowGroupConfiguration(
            title: "MenuBarExtra",
            size: IntSize(width: 400, height: 300),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content()), AnyView(label())],
            isMenuBarExtra: true
        )
    }

    public var body: Never {
        fatalError("MenuBarExtra has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}
@MainActor
public struct HandlesExternalEventsScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let conditions: Set<String>

    public init(content: Content, matching conditions: Set<String>) {
        self.content = content
        self.conditions = conditions
    }

    public var body: Never {
        fatalError("HandlesExternalEventsScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.handlesExternalEvents = conditions
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.handlesExternalEvents = conditions
            return configuration
        }
    }
}
extension Scene {
    public func handlesExternalEvents(matching conditions: Set<String>) -> some Scene {
        HandlesExternalEventsScene(content: self, matching: conditions)
    }
}
@MainActor
public struct ImmersionStyleScene<Content: Scene>: Scene {
    public typealias Body = Never
    private let content: Content
    public init(content: Content) {
        self.content = content
    }
    public var body: Never {
        fatalError("ImmersionStyleScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        content.makeWindowConfiguration()
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations()
    }
}
@MainActor
public struct VolumeBaseplateVisibilityScene<Content: Scene>: Scene {
    public typealias Body = Never
    private let content: Content
    public init(content: Content) {
        self.content = content
    }
    public var body: Never {
        fatalError("VolumeBaseplateVisibilityScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        content.makeWindowConfiguration()
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations()
    }
}
@MainActor
public struct PreferredSurroundingsEffectScene<Content: Scene>: Scene {
    public typealias Body = Never
    private let content: Content
    public init(content: Content) {
        self.content = content
    }
    public var body: Never {
        fatalError("PreferredSurroundingsEffectScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        content.makeWindowConfiguration()
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations()
    }
}
extension Scene {
    public func immersionStyle(selection: Binding<ImmersionStyle>, in allowedStyles: [ImmersionStyle]) -> some Scene {
        _ = selection
        _ = allowedStyles
        return ImmersionStyleScene(content: self)
    }

    public func volumeBaseplateVisibility(_ visibility: Visibility) -> some Scene {
        _ = visibility
        return VolumeBaseplateVisibilityScene(content: self)
    }

    public func preferredSurroundingsEffect(_ effect: SurroundingsEffect?) -> some Scene {
        _ = effect
        return PreferredSurroundingsEffectScene(content: self)
    }
}
public enum CommandGroupPlacement: Sendable {
    case appSettings
    case appTermination
    case appVisibility
    case newItem
    case openItem
    case saveItem
    case printItem
    case undoRedo
    case textEditing
    case findAndReplace
    case toolbar
    case sidebar
    case help
    case textFormatting
    case windowSize
    case windowArrangement
    case windowList
}
public struct CommandMenuDescriptor: Sendable {
    public var name: String
    public var content: [AnyView]

    public init(name: String, content: [AnyView]) {
        self.name = name
        self.content = content
    }
}
public struct CommandGroupDescriptor: Sendable {
    public var placement: CommandGroupPlacement
    public var content: [AnyView]
    public var replaces: Bool

    public init(placement: CommandGroupPlacement, content: [AnyView], replaces: Bool) {
        self.placement = placement
        self.content = content
        self.replaces = replaces
    }
}
public struct CommandsConfiguration: Sendable {
    public var menus: [CommandMenuDescriptor]
    public var groups: [CommandGroupDescriptor]

    public init(menus: [CommandMenuDescriptor] = [], groups: [CommandGroupDescriptor] = []) {
        self.menus = menus
        self.groups = groups
    }

    public static let empty = CommandsConfiguration()
}
@MainActor
public protocol Commands {
    associatedtype Body: Commands

    var body: Body { get }

    func makeCommandsConfiguration() -> CommandsConfiguration
}
extension Commands {
    public func makeCommandsConfiguration() -> CommandsConfiguration {
        body.makeCommandsConfiguration()
    }
}
extension Commands where Body == Never {
    public var body: Never {
        fatalError()
    }
}
extension Never: Commands {
    public func makeCommandsConfiguration() -> CommandsConfiguration {
        fatalError()
    }
}
@MainActor
public struct EmptyCommands: Commands {
    public typealias Body = Never

    public init() {}

    public func makeCommandsConfiguration() -> CommandsConfiguration {
        .empty
    }
}
@MainActor
public struct CommandMenu: Commands {
    public typealias Body = Never

    private let name: String
    private let content: [AnyView]

    public init(_ name: String, @ViewBuilder content: () -> [AnyView]) {
        self.name = name
        self.content = content()
    }

    public func makeCommandsConfiguration() -> CommandsConfiguration {
        CommandsConfiguration(menus: [CommandMenuDescriptor(name: name, content: content)])
    }
}
@MainActor
public struct CommandGroup: Commands {
    public typealias Body = Never

    private let placement: CommandGroupPlacement
    private let content: [AnyView]
    private let replaces: Bool

    public init(before: CommandGroupPlacement, @ViewBuilder addition: () -> [AnyView]) {
        self.placement = before
        self.content = addition()
        self.replaces = false
    }

    public init(after: CommandGroupPlacement, @ViewBuilder addition: () -> [AnyView]) {
        self.placement = after
        self.content = addition()
        self.replaces = false
    }

    public init(replacing: CommandGroupPlacement, @ViewBuilder addition: () -> [AnyView]) {
        self.placement = replacing
        self.content = addition()
        self.replaces = true
    }

    public func makeCommandsConfiguration() -> CommandsConfiguration {
        CommandsConfiguration(groups: [
            CommandGroupDescriptor(placement: placement, content: content, replaces: replaces)
        ])
    }
}
@MainActor
public struct ToolbarCommands: Commands {
    public typealias Body = Never

    public init() {}

    public func makeCommandsConfiguration() -> CommandsConfiguration {
        .empty
    }
}
@MainActor
public struct SidebarCommands: Commands {
    public typealias Body = Never

    public init() {}

    public func makeCommandsConfiguration() -> CommandsConfiguration {
        .empty
    }
}
@MainActor
public struct TextEditingCommands: Commands {
    public typealias Body = Never

    public init() {}

    public func makeCommandsConfiguration() -> CommandsConfiguration {
        .empty
    }
}
@MainActor
public struct InspectorCommands: Commands {
    public typealias Body = Never

    public init() {}

    public func makeCommandsConfiguration() -> CommandsConfiguration {
        .empty
    }
}
@MainActor
public struct HelpCommands: Commands {
    public typealias Body = Never

    public init() {}

    public func makeCommandsConfiguration() -> CommandsConfiguration {
        .empty
    }
}
@resultBuilder
public enum CommandsBuilder {
    public static func buildExpression(_ expression: CommandsConfiguration) -> CommandsConfiguration {
        expression
    }

    @MainActor
    public static func buildExpression<C: Commands>(_ expression: C) -> CommandsConfiguration {
        expression.makeCommandsConfiguration()
    }

    public static func buildBlock(_ configurations: CommandsConfiguration...) -> CommandsConfiguration {
        configurations.reduce(into: CommandsConfiguration()) { result, config in
            result.menus.append(contentsOf: config.menus)
            result.groups.append(contentsOf: config.groups)
        }
    }

    public static func buildOptional(_ configuration: CommandsConfiguration?) -> CommandsConfiguration {
        configuration ?? .empty
    }

    public static func buildEither(first configuration: CommandsConfiguration) -> CommandsConfiguration {
        configuration
    }

    public static func buildEither(second configuration: CommandsConfiguration) -> CommandsConfiguration {
        configuration
    }
}
@MainActor
public struct CommandsScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let commands: CommandsConfiguration

    public init(content: Content, commands: CommandsConfiguration) {
        self.content = content
        self.commands = commands
    }

    public var body: Never {
        fatalError("CommandsScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.commands = commands
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.commands = commands
            return configuration
        }
    }
}
extension Scene {
    public func commands(@CommandsBuilder _ commands: () -> CommandsConfiguration) -> some Scene {
        CommandsScene(content: self, commands: commands())
    }

    public func commandsRemoved() -> some Scene {
        CommandsScene(content: self, commands: .empty)
    }

    public func commandsReplaced(@CommandsBuilder _ commands: () -> CommandsConfiguration) -> some Scene {
        CommandsScene(content: self, commands: commands())
    }
}
@MainActor
public struct DefaultSizeScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let size: IntSize

    public init(content: Content, size: IntSize) {
        self.content = content
        self.size = size
    }

    public var body: Never {
        fatalError("DefaultSizeScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.size = size
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.size = size
            return configuration
        }
    }
}
@MainActor
public struct DefaultPositionScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let position: WindowPlacement

    public init(content: Content, position: WindowPlacement) {
        self.content = content
        self.position = position
    }

    public var body: Never {
        fatalError("DefaultPositionScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.defaultPosition = position
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.defaultPosition = position
            return configuration
        }
    }
}
@MainActor
public struct WindowResizabilityScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let resizability: WindowResizability

    public init(content: Content, resizability: WindowResizability) {
        self.content = content
        self.resizability = resizability
    }

    public var body: Never {
        fatalError("WindowResizabilityScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.resizability = resizability
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.resizability = resizability
            return configuration
        }
    }
}
@MainActor
public struct WindowToolbarStyleScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let toolbarStyle: WindowToolbarStyle

    public init(content: Content, toolbarStyle: WindowToolbarStyle) {
        self.content = content
        self.toolbarStyle = toolbarStyle
    }

    public var body: Never {
        fatalError("WindowToolbarStyleScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.toolbarStyle = toolbarStyle
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.toolbarStyle = toolbarStyle
            return configuration
        }
    }
}
extension Scene {
    public func defaultSize(_ size: IntSize) -> some Scene {
        DefaultSizeScene(content: self, size: size)
    }

    public func defaultPosition(_ position: WindowPlacement) -> some Scene {
        DefaultPositionScene(content: self, position: position)
    }

    public func defaultWindowPlacement(_ placement: WindowPlacement) -> some Scene {
        DefaultPositionScene(content: self, position: placement)
    }

    public func windowPlacement(_ placement: WindowPlacement) -> some Scene {
        DefaultPositionScene(content: self, position: placement)
    }

    public func windowResizability(_ resizability: WindowResizability) -> some Scene {
        WindowResizabilityScene(content: self, resizability: resizability)
    }

    public func windowToolbarStyle(_ style: WindowToolbarStyle) -> some Scene {
        WindowToolbarStyleScene(content: self, toolbarStyle: style)
    }

    public func menuBarExtraStyle(_ style: MenuBarExtraStyle) -> some Scene {
        MenuBarExtraStyleScene(content: self, style: style)
    }

    public func windowStyle(_ style: WindowStyle) -> some Scene {
        WindowStyleScene(content: self, style: style)
    }

    public func restorationBehavior(_ behavior: SceneRestorationBehavior) -> some Scene {
        RestorationBehaviorScene(content: self, behavior: behavior)
    }

    public func defaultLaunchBehavior(_ behavior: LaunchBehavior) -> some Scene {
        LaunchBehaviorScene(content: self, behavior: behavior)
    }

    public func windowActivationMode(_ mode: WindowActivationMode) -> some Scene {
        WindowActivationModeScene(content: self, mode: mode)
    }

    public func windowBackgroundDragBehavior(_ behavior: WindowBackgroundDragBehavior) -> some Scene {
        WindowBackgroundDragBehaviorScene(content: self, behavior: behavior)
    }

    public func windowSubtitle(_ subtitle: String?) -> some Scene {
        WindowSubtitleScene(content: self, subtitle: subtitle)
    }

    public func windowSubtitle<S: StringProtocol>(_ subtitle: S) -> some Scene {
        WindowSubtitleScene(content: self, subtitle: String(subtitle))
    }

    public func windowSubtitle(_ subtitleKey: LocalizedStringKey) -> some Scene {
        WindowSubtitleScene(content: self, subtitle: subtitleKey.resolvedString)
    }

    public func windowLevel(_ level: WindowLevel) -> some Scene {
        WindowLevelScene(content: self, level: level)
    }

    public func windowTitleBar(_ visibility: WindowTitleBarVisibility) -> some Scene {
        WindowTitleBarScene(content: self, titleBarVisibility: visibility)
    }

    public func windowMinSize(_ size: IntSize) -> some Scene {
        WindowMinSizeScene(content: self, size: size)
    }

    public func windowMaxSize(_ size: IntSize) -> some Scene {
        WindowMaxSizeScene(content: self, size: size)
    }

    public func windowIdealSize(_ size: IntSize) -> some Scene {
        WindowIdealSizeScene(content: self, size: size)
    }

    public func windowID(_ id: String) -> some Scene {
        WindowIDScene(content: self, id: id)
    }

    public func environment<Value>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) -> some Scene {
        EnvironmentScene(content: self, keyPath: keyPath, value: value)
    }

    public func defaultAppStorage(_ store: UserDefaults) -> some Scene {
        environment(\.defaultAppStorage, store)
    }

    public func defaultColorScheme(_ colorScheme: ColorScheme) -> some Scene {
        environment(\.colorScheme, colorScheme)
    }

    public func environmentObject<ObjectType: ObservableObject>(_ object: ObjectType) -> some Scene {
        EnvironmentObjectScene(content: self, object: object)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public func persistenceBehavior(_ behavior: ScenePersistenceBehavior) -> some Scene {
        PersistenceBehaviorScene(content: self, behavior: behavior)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public func windowManagerRole(_ role: WindowManagerRole) -> some Scene {
        WindowManagerRoleScene(content: self, role: role)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public func allowsWindowInlining(_ enabled: Bool = true) -> some Scene {
        AllowsWindowInliningScene(content: self, enabled: enabled)
    }
}
@MainActor
public struct MenuBarExtraStyleScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let style: MenuBarExtraStyle

    public init(content: Content, style: MenuBarExtraStyle) {
        self.content = content
        self.style = style
    }

    public var body: Never {
        fatalError("MenuBarExtraStyleScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.menuBarExtraStyle = style
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.menuBarExtraStyle = style
            return configuration
        }
    }
}
@MainActor
public struct WindowStyleScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let style: WindowStyle

    public init(content: Content, style: WindowStyle) {
        self.content = content
        self.style = style
    }

    public var body: Never {
        fatalError("WindowStyleScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.windowStyle = style
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.windowStyle = style
            return configuration
        }
    }
}
@MainActor
public struct RestorationBehaviorScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let behavior: SceneRestorationBehavior

    public init(content: Content, behavior: SceneRestorationBehavior) {
        self.content = content
        self.behavior = behavior
    }

    public var body: Never {
        fatalError("RestorationBehaviorScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.restorationBehavior = behavior
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.restorationBehavior = behavior
            return configuration
        }
    }
}
@MainActor
public struct LaunchBehaviorScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let behavior: LaunchBehavior

    public init(content: Content, behavior: LaunchBehavior) {
        self.content = content
        self.behavior = behavior
    }

    public var body: Never {
        fatalError("LaunchBehaviorScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.launchBehavior = behavior
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.launchBehavior = behavior
            return configuration
        }
    }
}
@MainActor
public struct WindowActivationModeScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let mode: WindowActivationMode

    public init(content: Content, mode: WindowActivationMode) {
        self.content = content
        self.mode = mode
    }

    public var body: Never {
        fatalError("WindowActivationModeScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.activationMode = mode
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.activationMode = mode
            return configuration
        }
    }
}
@MainActor
public struct WindowBackgroundDragBehaviorScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let behavior: WindowBackgroundDragBehavior

    public init(content: Content, behavior: WindowBackgroundDragBehavior) {
        self.content = content
        self.behavior = behavior
    }

    public var body: Never {
        fatalError("WindowBackgroundDragBehaviorScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.backgroundDragBehavior = behavior
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.backgroundDragBehavior = behavior
            return configuration
        }
    }
}
@MainActor
public struct WindowSubtitleScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let subtitle: String?

    public init(content: Content, subtitle: String?) {
        self.content = content
        self.subtitle = subtitle
    }

    public var body: Never {
        fatalError("WindowSubtitleScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.subtitle = subtitle
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.subtitle = subtitle
            return configuration
        }
    }
}
@MainActor
public struct WindowLevelScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let level: WindowLevel

    public init(content: Content, level: WindowLevel) {
        self.content = content
        self.level = level
    }

    public var body: Never {
        fatalError("WindowLevelScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.windowLevel = level
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.windowLevel = level
            return configuration
        }
    }
}
@MainActor
public struct WindowTitleBarScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let titleBarVisibility: WindowTitleBarVisibility

    public init(content: Content, titleBarVisibility: WindowTitleBarVisibility) {
        self.content = content
        self.titleBarVisibility = titleBarVisibility
    }

    public var body: Never {
        fatalError("WindowTitleBarScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.titleBarVisibility = titleBarVisibility
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.titleBarVisibility = titleBarVisibility
            return configuration
        }
    }
}
@MainActor
public struct WindowMinSizeScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let size: IntSize

    public init(content: Content, size: IntSize) {
        self.content = content
        self.size = size
    }

    public var body: Never {
        fatalError("WindowMinSizeScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.minSize = size
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.minSize = size
            return configuration
        }
    }
}
@MainActor
public struct WindowMaxSizeScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let size: IntSize

    public init(content: Content, size: IntSize) {
        self.content = content
        self.size = size
    }

    public var body: Never {
        fatalError("WindowMaxSizeScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.maxSize = size
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.maxSize = size
            return configuration
        }
    }
}
@MainActor
public struct WindowIdealSizeScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let size: IntSize

    public init(content: Content, size: IntSize) {
        self.content = content
        self.size = size
    }

    public var body: Never {
        fatalError("WindowIdealSizeScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.idealSize = size
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.idealSize = size
            return configuration
        }
    }
}
@MainActor
public struct WindowIDScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let id: String

    public init(content: Content, id: String) {
        self.content = content
        self.id = id
    }

    public var body: Never {
        fatalError("WindowIDScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.windowID = id
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.windowID = id
            return configuration
        }
    }
}
@MainActor
public struct EnvironmentScene<Content: Scene, Value>: Scene {
    public typealias Body = Never

    private let content: Content
    private let keyPath: WritableKeyPath<EnvironmentValues, Value>
    private let value: Value

    public init(content: Content, keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
        self.content = content
        self.keyPath = keyPath
        self.value = value
    }

    public var body: Never {
        fatalError("EnvironmentScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        applyingEnvironment(to: content.makeWindowConfiguration())
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map { applyingEnvironment(to: $0) }
    }

    private func applyingEnvironment(to original: WindowGroupConfiguration) -> WindowGroupConfiguration {
        var configuration = original
        let buildWindowContent = configuration.windowContentFactory
        configuration.content = configuration.content.map {
            $0.mappingViewIdentity { AnyView($0.environment(keyPath, value)) }
        }
        if let buildContent = buildWindowContent {
            configuration.windowContentFactory = {
                buildContent().map { $0.mappingViewIdentity { AnyView($0.environment(keyPath, value)) } }
            }
        }
        if let buildContent = configuration.dataBoundContent {
            configuration.dataBoundContent = { payload in
                buildContent(payload).map { $0.mappingViewIdentity { AnyView($0.environment(keyPath, value)) } }
            }
        }
        configuration.documentScene = configuration.documentScene?.mappingContent { views in
            views.map { $0.mappingViewIdentity { AnyView($0.environment(keyPath, value)) } }
        }
        return configuration
    }
}
@MainActor
public struct EnvironmentObjectScene<Content: Scene, ObjectType: ObservableObject>: Scene {
    public typealias Body = Never

    private let content: Content
    private let object: ObjectType

    public init(content: Content, object: ObjectType) {
        self.content = content
        self.object = object
    }

    public var body: Never {
        fatalError("EnvironmentObjectScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        applyingEnvironmentObject(to: content.makeWindowConfiguration())
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map { applyingEnvironmentObject(to: $0) }
    }

    private func applyingEnvironmentObject(to original: WindowGroupConfiguration) -> WindowGroupConfiguration {
        var configuration = original
        let buildWindowContent = configuration.windowContentFactory
        configuration.content = configuration.content.map {
            $0.mappingViewIdentity { AnyView($0.environmentObject(object)) }
        }
        if let buildContent = buildWindowContent {
            configuration.windowContentFactory = {
                buildContent().map { $0.mappingViewIdentity { AnyView($0.environmentObject(object)) } }
            }
        }
        if let buildContent = configuration.dataBoundContent {
            configuration.dataBoundContent = { payload in
                buildContent(payload).map { $0.mappingViewIdentity { AnyView($0.environmentObject(object)) } }
            }
        }
        configuration.documentScene = configuration.documentScene?.mappingContent { views in
            views.map { $0.mappingViewIdentity { AnyView($0.environmentObject(object)) } }
        }
        return configuration
    }
}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@MainActor
public struct PersistenceBehaviorScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let behavior: ScenePersistenceBehavior

    public init(content: Content, behavior: ScenePersistenceBehavior) {
        self.content = content
        self.behavior = behavior
    }

    public var body: Never {
        fatalError("PersistenceBehaviorScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.persistenceBehavior = behavior
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.persistenceBehavior = behavior
            return configuration
        }
    }
}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@MainActor
public struct WindowManagerRoleScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let role: WindowManagerRole

    public init(content: Content, role: WindowManagerRole) {
        self.content = content
        self.role = role
    }

    public var body: Never {
        fatalError("WindowManagerRoleScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.windowManagerRole = role
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.windowManagerRole = role
            return configuration
        }
    }
}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@MainActor
public struct AllowsWindowInliningScene<Content: Scene>: Scene {
    public typealias Body = Never

    private let content: Content
    private let enabled: Bool

    public init(content: Content, enabled: Bool) {
        self.content = content
        self.enabled = enabled
    }

    public var body: Never {
        fatalError("AllowsWindowInliningScene has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        var configuration = content.makeWindowConfiguration()
        configuration.allowsWindowInlining = enabled
        return configuration
    }

    public func makeWindowConfigurations() -> [WindowGroupConfiguration] {
        content.makeWindowConfigurations().map {
            var configuration = $0
            configuration.allowsWindowInlining = enabled
            return configuration
        }
    }
}
/// Erases the model type through operations implemented by a typed adapter;
/// document values never travel through Any or a value-window payload.
@MainActor
protocol AnyDocumentSession: AnyObject {
    var sessionID: UUID { get }
    var fileURL: URL? { get }
    var isEditable: Bool { get }
    var isDirty: Bool { get }
    var mutationRevision: UInt64 { get }
    var currentCheckpoint: DocumentCheckpoint { get }
    var savedCheckpoint: DocumentCheckpoint? { get }
    var savedBytes: Data? { get }
    var lastError: Error? { get }
    var hasActiveOperation: Bool { get }
    var pendingCloseIntent: DocumentCloseIntent? { get }
    var closeApproval: DocumentCloseApproval? { get }
    var closePhase: DocumentClosePhase { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func makeContent() -> [AnyView]
    func save() -> DocumentSaveOutcome
    func saveAs() -> DocumentSaveOutcome
    func save(to url: URL) -> DocumentSaveOutcome
    func requestClose(isHostSettled: Bool) -> DocumentCloseRequest
    func resolveCloseIntent(id: UUID, choice: DocumentCloseChoice) -> DocumentCloseResolution
    func invalidateCloseForHostChange()
    func reserveClose(approval: DocumentCloseApproval, isHostSettled: Bool) -> Bool
    func releaseCloseReservation(_ approval: DocumentCloseApproval)
    func invalidate()
}

@MainActor
private final class DocumentSessionAdapter<Document: FileDocument>: AnyDocumentSession {
    let session: FileDocumentSession<Document>
    private let content: @MainActor (FileDocumentConfiguration<Document>) -> [AnyView]

    init(
        session: FileDocumentSession<Document>,
        content: @escaping @MainActor (FileDocumentConfiguration<Document>) -> [AnyView]
    ) {
        self.session = session
        self.content = content
    }

    var sessionID: UUID { session.sessionID }
    var fileURL: URL? { session.fileURL }
    var isEditable: Bool { session.isEditable }
    var isDirty: Bool { session.isDirty }
    var mutationRevision: UInt64 { session.mutationRevision }
    var currentCheckpoint: DocumentCheckpoint { session.currentCheckpoint }
    var savedCheckpoint: DocumentCheckpoint? { session.savedCheckpoint }
    var savedBytes: Data? { session.savedBytes }
    var lastError: Error? { session.lastError }
    var hasActiveOperation: Bool { session.hasActiveOperation }
    var pendingCloseIntent: DocumentCloseIntent? { session.pendingCloseIntent }
    var closeApproval: DocumentCloseApproval? { session.closeApproval }
    var closePhase: DocumentClosePhase { session.closePhase }
    var onChange: (@MainActor () -> Void)? {
        get { session.onChange }
        set { session.onChange = newValue }
    }

    func makeContent() -> [AnyView] { content(session.configuration()) }
    func save() -> DocumentSaveOutcome { session.save() }
    func saveAs() -> DocumentSaveOutcome { session.saveAs() }
    func save(to url: URL) -> DocumentSaveOutcome { session.save(to: url) }
    func requestClose(isHostSettled: Bool) -> DocumentCloseRequest {
        session.requestClose(isHostSettled: isHostSettled)
    }
    func resolveCloseIntent(id: UUID, choice: DocumentCloseChoice) -> DocumentCloseResolution {
        session.resolveCloseIntent(id: id, choice: choice)
    }
    func invalidateCloseForHostChange() { session.invalidateCloseForHostChange() }
    func reserveClose(approval: DocumentCloseApproval, isHostSettled: Bool) -> Bool {
        session.reserveClose(approval: approval, isHostSettled: isHostSettled)
    }
    func releaseCloseReservation(_ approval: DocumentCloseApproval) { session.releaseCloseReservation(approval) }
    func invalidate() { session.invalidate() }
}

@MainActor
struct DocumentSessionDependencies {
    let owner: DocumentOwnerLease
    let files: any DocumentFileService
    let undoManager: UndoManager?
}

/// Immutable declaration metadata plus typed factories. Creating a scene does
/// not invoke a document factory, read an empty wrapper, or build editor views.
@MainActor
struct DocumentSceneDescriptor {
    let id: UUID
    let validateDocumentType: @MainActor () throws -> Void
    let readableContentTypes: @MainActor () -> [UTType]
    let makeNew: (@MainActor (UTType, DocumentSessionDependencies) throws -> any AnyDocumentSession)?
    let read: @MainActor (Data, URL, UTType, DocumentSessionDependencies) throws -> any AnyDocumentSession
    private var contentMappings: [@MainActor ([AnyView]) -> [AnyView]] = []

    init<Document: FileDocument>(
        documentType: Document.Type,
        codec: DocumentCodec<Document>,
        newDocument: (@MainActor () -> Document)?,
        isEditable: Bool,
        content: @escaping @MainActor (FileDocumentConfiguration<Document>) -> [AnyView]
    ) {
        id = UUID()
        validateDocumentType = {
            guard !(Document.self is AnyClass) else { throw DocumentSessionError.referenceDocumentUnsupported }
        }
        readableContentTypes = { documentType.readableContentTypes }
        if let newDocument {
            makeNew = { type, dependencies in
                guard !(Document.self is AnyClass) else { throw DocumentSessionError.referenceDocumentUnsupported }
                let document = newDocument()
                guard dependencies.owner.isValid else { throw DocumentSessionError.ownerUnavailable }
                return DocumentSessionAdapter(
                    session: try FileDocumentSession(
                        document: document, contentType: type, isEditable: isEditable,
                        owner: dependencies.owner, codec: codec, files: dependencies.files,
                        undoManager: dependencies.undoManager
                    ),
                    content: content
                )
            }
        } else {
            makeNew = nil
        }
        read = { data, url, type, dependencies in
            guard !(Document.self is AnyClass) else { throw DocumentSessionError.referenceDocumentUnsupported }
            let document = try codec.decode(data, type)
            guard dependencies.owner.isValid else { throw DocumentSessionError.ownerUnavailable }
            return DocumentSessionAdapter(
                session: try FileDocumentSession(
                    document: document, fileURL: url, contentType: type, isEditable: isEditable,
                    owner: dependencies.owner, codec: codec, files: dependencies.files,
                    undoManager: dependencies.undoManager, savedBytes: data
                ),
                content: content
            )
        }
    }

    private init() {
        id = UUID()
        validateDocumentType = { throw DocumentSessionError.referenceDocumentUnsupported }
        readableContentTypes = { [] }
        makeNew = nil
        read = { _, _, _, _ in throw DocumentSessionError.referenceDocumentUnsupported }
    }

    static var unsupportedReferenceDocument: Self { Self() }

    func mappingContent(_ mapping: @escaping @MainActor ([AnyView]) -> [AnyView]) -> Self {
        var copy = self
        copy.contentMappings.append(mapping)
        return copy
    }

    func mapContent(_ views: [AnyView]) -> [AnyView] {
        contentMappings.reduce(views) { views, mapping in mapping(views) }
    }
}

/// This stage deliberately has no native capability constructor. The private
/// initializer makes the explicit headless seam distinct from a missing HWND
/// (which is also normal during real window construction).
@MainActor
struct DocumentWindowServices {
    let files: any DocumentFileService
    let maximumReadBytes: Int
    let makeUndoManager: @MainActor () -> UndoManager?

    private init(
        files: any DocumentFileService,
        maximumReadBytes: Int,
        makeUndoManager: @escaping @MainActor () -> UndoManager?
    ) {
        self.files = files
        // The synchronous hosted stage has a ceiling, not an opt-out knob.
        // Tests may lower it; negative limits retain the service's error path.
        self.maximumReadBytes = min(maximumReadBytes, LiveDocumentFileService.defaultMaximumReadBytes)
        self.makeUndoManager = makeUndoManager
    }

    static func headless(
        files: any DocumentFileService,
        maximumReadBytes: Int = LiveDocumentFileService.defaultMaximumReadBytes,
        makeUndoManager: @escaping @MainActor () -> UndoManager? = { UndoManager() }
    ) -> Self {
        Self(files: files, maximumReadBytes: maximumReadBytes, makeUndoManager: makeUndoManager)
    }
}

@MainActor
final class DocumentWindowContext {
    struct RoutingTicket: Equatable {
        let id: UUID
        let ownerGeneration: UInt64
        let sessionID: UUID
        let mutationRevision: UInt64
    }

    let descriptor: DocumentSceneDescriptor
    let owner: DocumentOwnerLease
    let session: any AnyDocumentSession
    let services: DocumentWindowServices
    let undoManager: UndoManager?
    var environment: WindowSceneEnvironment
    private(set) weak var host: WinSwiftUIWindowHost?
    private(set) var routingError: Error?
    private var routingTicket: RoutingTicket?
    private var invalidateContent: (@MainActor () -> Void)?

    init(
        descriptor: DocumentSceneDescriptor, owner: DocumentOwnerLease,
        session: any AnyDocumentSession, services: DocumentWindowServices,
        undoManager: UndoManager?, sceneStorageScope: String
    ) {
        self.descriptor = descriptor
        self.owner = owner
        self.session = session
        self.services = services
        self.undoManager = undoManager
        environment = WindowSceneEnvironment(
            openWindow: .noop, dismissWindow: .noop,
            supportsMultipleWindows: true, sceneStorageScope: sceneStorageScope
        )
    }

    var isRoutingDocument: Bool { routingTicket != nil }
    var lastError: Error? { routingError ?? session.lastError }

    func bind(
        host: WinSwiftUIWindowHost, runtime: RetainedViewRuntime,
        dialogOwner: @escaping @MainActor () -> FileDialogOwner,
        invalidate: @escaping @MainActor () -> Void
    ) {
        guard owner.isValid, self.host == nil else { return }
        self.host = host
        owner.bind(runtime: runtime, dialogOwner: dialogOwner)
        invalidateContent = invalidate
        session.onChange = invalidate
    }

    func makeContent() -> [AnyView] {
        guard owner.isValid else { return [] }
        let content = session.makeContent()
        guard owner.isValid else { return [] }
        let mapped = descriptor.mapContent(content)
        return owner.isValid ? mapped : []
    }

    func beginRouting() throws -> RoutingTicket {
        guard owner.isValid else { throw DocumentSessionError.ownerUnavailable }
        guard routingTicket == nil, !session.hasActiveOperation,
            !owner.hasCloseCommitReservation, host?.canStartDocumentOperation == true
        else { throw WindowCoordinatorError.documentOperationBusy }
        let ticket = RoutingTicket(
            id: UUID(), ownerGeneration: owner.generation,
            sessionID: session.sessionID, mutationRevision: session.mutationRevision
        )
        routingTicket = ticket
        if routingError != nil {
            var displacedError = routingError
            routingError = nil
            withExtendedLifetime(displacedError) {}
            displacedError = nil
            invalidateContent?()
        }
        do {
            try validate(ticket)
        } catch {
            finishRouting(ticket)
            throw error
        }
        return ticket
    }

    func validate(_ ticket: RoutingTicket) throws {
        guard owner.isValid, owner.generation == ticket.ownerGeneration,
            routingTicket == ticket, session.sessionID == ticket.sessionID,
            session.mutationRevision == ticket.mutationRevision,
            !owner.hasCloseCommitReservation, !session.hasActiveOperation,
            host?.canStartDocumentOperation == true
        else { throw DocumentSessionError.supersededOperation }
    }

    func finishRouting(_ ticket: RoutingTicket) {
        if routingTicket == ticket { routingTicket = nil }
    }

    func reportRoutingError(_ error: Error) {
        guard owner.isValid, !owner.hasCloseCommitReservation else { return }
        routingError = error
        invalidateContent?()
    }

    func save() -> DocumentSaveOutcome { performSave { session.save() } }
    func saveAs() -> DocumentSaveOutcome { performSave { session.saveAs() } }
    func save(to url: URL) -> DocumentSaveOutcome { performSave { session.save(to: url) } }

    private func performSave(_ save: () -> DocumentSaveOutcome) -> DocumentSaveOutcome {
        guard owner.isValid else { return .superseded(written: nil) }
        let ticket: RoutingTicket
        do {
            // Acquire context authority before releasing an old Error payload
            // or publishing its removal. Either can synchronously reenter.
            ticket = try beginRouting()
        } catch WindowCoordinatorError.documentOperationBusy {
            return .busy
        } catch {
            return .superseded(written: nil)
        }
        defer { finishRouting(ticket) }
        return save()
    }

    func invalidate() {
        owner.revoke()
        routingTicket = nil
        session.invalidate()
        routingError = nil
        invalidateContent = nil
    }
}

public struct WindowGroupConfiguration {
    public var title: String
    public var size: IntSize
    public var clearColor: Color
    public var content: [AnyView] {
        didSet { windowContentFactory = nil }
    }
    /// The declaration's content remains inspectable, but each ordinary
    /// WindowGroup window gets fresh root view values. A materialized host
    /// keeps those values through its own observed-object rebuilds.
    var windowContentFactory: (@MainActor () -> [AnyView])?
    var documentScene: DocumentSceneDescriptor?
    var documentWindowContext: DocumentWindowContext?
    public var handlesExternalEvents: Set<String>?
    public var windowID: String?
    public var isSettingsWindow: Bool
    public var isDocumentGroup: Bool
    public var isMenuBarExtra: Bool
    public var commands: CommandsConfiguration?
    public var minSize: IntSize?
    public var maxSize: IntSize?
    public var idealSize: IntSize?
    public var defaultPosition: WindowPlacement?
    public var resizability: WindowResizability?
    public var toolbarStyle: WindowToolbarStyle?
    public var menuBarExtraStyle: MenuBarExtraStyle?
    public var windowStyle: WindowStyle?
    public var restorationBehavior: SceneRestorationBehavior?
    public var launchBehavior: LaunchBehavior?
    public var activationMode: WindowActivationMode?
    public var backgroundDragBehavior: WindowBackgroundDragBehavior?
    public var subtitle: String?
    public var windowLevel: WindowLevel?
    public var titleBarVisibility: WindowTitleBarVisibility?
    public var persistenceBehavior: ScenePersistenceBehavior?
    public var windowManagerRole: WindowManagerRole?
    public var allowsWindowInlining: Bool?
    public var resizeToContents: Bool?
    public var forType: Any.Type?
    public var dataBoundContent: ((AnyHashable) -> [AnyView])?

    public init(
        title: String,
        size: IntSize,
        clearColor: Color,
        content: [AnyView],
        windowID: String? = nil,
        isSettingsWindow: Bool = false,
        isDocumentGroup: Bool = false,
        isMenuBarExtra: Bool = false,
        commands: CommandsConfiguration? = nil,
        minSize: IntSize? = nil,
        maxSize: IntSize? = nil,
        idealSize: IntSize? = nil,
        defaultPosition: WindowPlacement? = nil,
        resizability: WindowResizability? = nil,
        toolbarStyle: WindowToolbarStyle? = nil,
        menuBarExtraStyle: MenuBarExtraStyle? = nil,
        windowStyle: WindowStyle? = nil,
        restorationBehavior: SceneRestorationBehavior? = nil,
        launchBehavior: LaunchBehavior? = nil,
        activationMode: WindowActivationMode? = nil,
        backgroundDragBehavior: WindowBackgroundDragBehavior? = nil,
        subtitle: String? = nil,
        windowLevel: WindowLevel? = nil,
        titleBarVisibility: WindowTitleBarVisibility? = nil,
        persistenceBehavior: ScenePersistenceBehavior? = nil,
        windowManagerRole: WindowManagerRole? = nil,
        allowsWindowInlining: Bool? = nil,
        resizeToContents: Bool? = nil,
        forType: Any.Type? = nil,
        dataBoundContent: ((AnyHashable) -> [AnyView])? = nil
    ) {
        self.title = title
        self.size = size
        self.clearColor = clearColor
        self.content = content
        self.windowID = windowID
        self.isSettingsWindow = isSettingsWindow
        self.isDocumentGroup = isDocumentGroup
        self.isMenuBarExtra = isMenuBarExtra
        self.titleBarVisibility = titleBarVisibility
        self.commands = commands
        self.minSize = minSize
        self.maxSize = maxSize
        self.idealSize = idealSize
        self.defaultPosition = defaultPosition
        self.forType = forType
        self.dataBoundContent = dataBoundContent
        self.resizability = resizability
        self.toolbarStyle = toolbarStyle
        self.menuBarExtraStyle = menuBarExtraStyle
        self.windowStyle = windowStyle
        self.restorationBehavior = restorationBehavior
        self.launchBehavior = launchBehavior
        self.activationMode = activationMode
        self.backgroundDragBehavior = backgroundDragBehavior
        self.subtitle = subtitle
        self.windowLevel = windowLevel
        self.persistenceBehavior = persistenceBehavior
        self.windowManagerRole = windowManagerRole
        self.allowsWindowInlining = allowsWindowInlining
        self.resizeToContents = resizeToContents
    }

    @MainActor
    mutating func instantiateWindowContent() {
        guard let buildContent = windowContentFactory else { return }
        content = buildContent()
        windowContentFactory = nil
    }
}
enum WindowHostInputEvent {
    case pointerMoved(point: Point, scaleFactor: Double)
    case pointerExitedWindow
    case mouseWheel(point: Point, delta: Double, axis: ScrollAxis?, scaleFactor: Double)
    case pointerDown(point: Point, scaleFactor: Double)
    case pointerUp(point: Point, scaleFactor: Double)
    case pointerCancelled
    case contextClick(point: Point, scaleFactor: Double)
    case keyDown(KeyboardEvent)
    case textInput(String)
    case keyboardFocusDidLeaveWindow
}
/// Per-window environment installed by `WinSwiftUIWindowCoordinator`. Hosts
/// created without a coordinator keep the historical defaults: no-op window
/// actions, `supportsMultipleWindows == false`, and the shared scene-storage
/// scope.
struct WindowSceneEnvironment {
    var openWindow: OpenWindowAction
    var dismissWindow: DismissWindowAction
    var supportsMultipleWindows: Bool
    var sceneStorageScope: String
    var openSettings: OpenSettingsAction = .noop
    var newDocument: NewDocumentAction = .noop
    var openDocument: OpenDocumentAction = .noop
    var saveDocument: SaveDocumentAction = .noop
}

/// A package-owned session can add its own close decision without replacing
/// the concrete or renderer-neutral delegate votes. A participant holds its
/// host weakly. Its prepared lease pins the actual session until finish.
@MainActor
protocol WindowCloseParticipant: AnyObject {
    func windowShouldClose(_ attempt: Win32CloseAttempt) -> Bool
    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation

    /// Revoke owner capabilities using stored framework state only. Do not
    /// release application payloads or deliver callbacks before host teardown
    /// has also revoked editor and mounted-State capabilities.
    func revokeCloseParticipation()
}

enum WindowCloseWorkSubmission: Equatable {
    case queued
    case waitingForBuilds
    case coalesced
    case busy
    case unavailable
    case postFailed(UInt32)

    init(_ submission: Win32DeferredCloseSubmission) {
        switch submission {
        case .queued: self = .queued
        case .coalesced: self = .coalesced
        case .busy: self = .busy
        case .unavailable: self = .unavailable
        case .postFailed(let code): self = .postFailed(code)
        }
    }
}

@MainActor
final class WinSwiftUIWindowHost: WindowDelegate, Win32CloseAuthority {
    private final class CloseParticipantIdentity {}
    private final class CloseReservation {}

    private struct ClosePreflightStamp {
        let receipt: RetainedLayoutSettlementReceipt
        let behavior: RetainedWindowInteractionBehavior
        let registration: Win32CloseRegistration
    }

    /// Kept through terminal callbacks so reentry into the same native attempt
    /// cannot replace its first receipt. None of this state retains app data.
    private final class ClosePreflight {
        let attempt: Win32CloseAttempt
        let participantIdentity: CloseParticipantIdentity
        var stamp: ClosePreflightStamp?
        var vote: Win32CloseCommitDecision?
        var hasFinished = false

        init(attempt: Win32CloseAttempt, participantIdentity: CloseParticipantIdentity) {
            self.attempt = attempt
            self.participantIdentity = participantIdentity
        }
    }

    private final class CloseBuildWait {
        let ticket: Win32CloseTicket
        let phase: Win32DeferredClosePhase
        let registration: Win32CloseRegistration
        let participantIdentity: CloseParticipantIdentity
        weak var participant: (any WindowCloseParticipant)?
        let action: @MainActor (Win32CloseTicket) -> Void
        let onSubmissionFailure: @MainActor (Win32CloseTicket, Win32DeferredCloseSubmission) -> Void
        var isValid = true
        var isWaiting = false
        var coordinatorObserverPending = false
        var isRegistering = false
        var submission: Win32DeferredCloseSubmission?
        var hasPublishedFailure = false

        init(
            ticket: Win32CloseTicket, phase: Win32DeferredClosePhase, registration: Win32CloseRegistration,
            participantIdentity: CloseParticipantIdentity, participant: any WindowCloseParticipant,
            onSubmissionFailure: @escaping @MainActor (Win32CloseTicket, Win32DeferredCloseSubmission) -> Void,
            action: @escaping @MainActor (Win32CloseTicket) -> Void
        ) {
            self.ticket = ticket
            self.phase = phase
            self.registration = registration
            self.participantIdentity = participantIdentity
            self.participant = participant
            self.onSubmissionFailure = onSubmissionFailure
            self.action = action
        }
    }

    private final class CloseCommitLease: Win32CloseCommitLease {
        let host: WinSwiftUIWindowHost
        let preflight: ClosePreflight
        let stamp: ClosePreflightStamp
        let participant: (any WindowCloseParticipant)?
        let participantLease: (any Win32CloseCommitLease)?
        let reservation = CloseReservation()
        private var didValidate = false
        private var didFinish = false

        init(
            host: WinSwiftUIWindowHost, preflight: ClosePreflight, stamp: ClosePreflightStamp,
            participant: (any WindowCloseParticipant)?, participantLease: (any Win32CloseCommitLease)?
        ) {
            self.host = host
            self.preflight = preflight
            self.stamp = stamp
            self.participant = participant
            self.participantLease = participantLease
        }

        func validateAndReserve() -> Win32CloseCommitDecision {
            guard !didValidate, !didFinish else { return .unavailable }
            didValidate = true
            let before = host.validateClosePreflight(preflight, stamp: stamp)
            guard before == .reserved else { return before }

            // Allocate the token during preparation, then publish only a
            // reference here. Slot replacement stays blocked through finish.
            host.closeCommitReservation = reservation
            if let participantLease {
                let decision = participantLease.validateAndReserve()
                guard decision == .reserved else { return decision }
            }
            return host.validateClosePreflight(preflight, stamp: stamp, reservation: reservation)
        }

        func finish(with outcome: Win32CloseAttemptOutcome) {
            guard !didFinish else { return }
            didFinish = true
            preflight.hasFinished = true
            participantLease?.finish(with: outcome)
            if !host.hasTornDownWindow, host.closeCommitReservation === reservation {
                host.closeCommitReservation = nil
            }
            withExtendedLifetime(participant) {}
        }
    }

    private enum PresentationBackend {
        case frame
        case scene
    }

    private let configuration: WindowGroupConfiguration
    private let window: Win32Window
    private let renderer: any RenderBackend
    private let batchRenderer: (any BatchRenderBackend)?
    private let runtime: RetainedViewRuntime
    private let componentHost: ComponentHost
    private lazy var stateMountCoordinator = StateMountCoordinator(
        invalidate: { [weak self] in
            self?.reloadContentFromView(isStateMutation: true)
        },
        observeObject: { [weak self] object in
            self?.observeObject(object)
        },
        updateObservedObjects: { [weak self] committed, retained, replacesRoot in
            self?.updateObservedObjects(committed: committed, retained: retained, replacesRoot: replacesRoot)
        },
        reportInstallationError: { [weak self] message in
            self?.reportRepeating(message, signature: "state-installation:\(message)")
        }
    )
    private let surfaceDescriptorProvider: @MainActor (Win32Window) -> SurfaceDescriptor?
    private let sceneRenderer: @MainActor (RetainedViewRuntime, Double) -> GPUIScene
    private let startupPresentationMode: StartupPresentationMode
    private let startupProbeConfiguration: StartupProbeConfiguration?
    /// What the composition root's availability probe decided, or `nil` for
    /// hosts built without one (tests, direct embedders). Read-only: the host
    /// reports it, it never acts on it.
    private let backendResolution: RenderBackendResolution?
    private let inputRateTracker = WindowInputRateTracker()
    private let undoManager: UndoManager?
    private var isPrimaryTouchActive = false
    private var hasTornDownWindow = false
    private var isPerformingInitialContentBuild = true
    private var isEvaluatingWindowClosePolicy = false
    private var isPreparingWindowCloseCommit = false
    private var isReplacingWindowCloseParticipant = false
    private var isSubmittingWindowCloseWork = false
    private var windowCloseParticipant: (any WindowCloseParticipant)?
    private var closeParticipantIdentity = CloseParticipantIdentity()
    private var closePreflight: ClosePreflight?
    private var closeCommitReservation: CloseReservation?
    private var pendingCloseBuildWait: CloseBuildWait?
    private(set) var windowCloseRegistration: Win32CloseRegistration?
    private(set) var documentActivationError: Error?
    private var claimedDocumentContext: DocumentWindowContext?
    private var lastDocumentDismissBehavior: RetainedWindowInteractionBehavior?

    /// Where a pacing verdict outlives the process, or `nil` for hosts that
    /// do not persist one (tests, direct embedders). See
    /// ``PresentPacingMemoryStore``; the production coordinator passes the
    /// per-user standard store.
    private let presentPacingMemory: PresentPacingMemoryStore?
    /// The adapter+display key this window's verdict is filed under.
    /// Computed at presenter attach and refreshed on display change.
    private var presentPacingMemoryKey: String?
    /// The verdict last handed to the store, so the frame loop's bookkeeping
    /// is one comparison per frame rather than one store call.
    private var lastPersistedPacingVerdict: Bool?

    // UI Automation bridge (Phase 2): exposes the retained tree to UIA via
    // WM_GETOBJECT and raises focus/structure events. Owned for the window's
    // lifetime; provider callbacks re-project live state on every call.
    private var uiaBridge: UIAProviderBridge?
    private var uiaTreeSource: RuntimeUIAElementTreeSource?

    private var isRendererReady = false
    private var activeBackend: PresentationBackend = .frame
    private var surfaceDescriptor: SurfaceDescriptor?

    // MARK: Presenter attach retry (no-presenter wedge)
    //
    // A window with no attached backend used to re-`InvalidateRect` itself
    // from the not-ready branch of the render path. That branch runs inside
    // `WM_PAINT`'s BeginPaint/EndPaint pair, so the invalidation re-dirtied
    // the region `BeginPaint` had just validated: one core at 100 % behind a
    // blank window for the life of the process, on any machine where device
    // creation fails for both backends. The replacement is a bounded retry on
    // the frame timer's own coarse cadence, followed by a terminal state that
    // stops asking for frames and is visible in `RendererHealthSnapshot`.

    /// Attach attempts made since the last successful attach.
    private var presenterAttachAttemptCount = 0
    /// Wall-clock timestamp of the next attach retry, `nil` when none is
    /// scheduled (a presenter is attached, or the terminal state was reached).
    private var nextPresenterAttachAttemptAt: Double?
    /// Terminal state: no backend could be attached within the retry budget.
    /// The host stops driving frames; the window keeps servicing input and
    /// resizes so the app is closable and can still recover on an explicit
    /// re-attach.
    private(set) var isPresenterUnavailable = false
    /// Detail of the most recent attach failure, carried into the selection
    /// reason so the terminal state is actionable rather than silent.
    private var lastPresenterAttachFailureDetail = "No render backend attached."

    /// Recurrence counts per distinct failure signature, used to rate-limit
    /// `report`. Bounded by `maximumTrackedFailureSignatures`.
    private var reportedFailureCounts: [String: Int] = [:]
    private var didReportFailureSignatureOverflow = false

    /// Number of lines this host has actually emitted through `report`.
    /// Exposed so tests can prove a per-frame failure logs O(1), not O(frames).
    private(set) var emittedReportCount = 0

    private static let maximumTrackedFailureSignatures = 16
    private static let repeatedFailureReportInterval = 100

    private static let maximumPresenterAttachAttempts = 5
    private static let initialPresenterAttachRetryInterval: Double = 0.5
    private static let maximumPresenterAttachRetryInterval: Double = 8.0
    /// Retry cadence for the frame timer while no presenter is attached.
    /// Deliberately far coarser than the frame interval: nothing is being
    /// painted, and the only work per tick is a clock comparison.
    private static let presenterAttachRetryIntervalMilliseconds: UInt32 = 250

    /// Configured at init. When `isEnabled`, the host periodically tries to
    /// re-attach the batch backend after a downgrade.
    private let recoveryPolicy: BatchBackendRecoveryPolicy
    /// Wall-clock timestamp (seconds) of the next batch-recovery attempt, or
    /// `nil` while batch is the active backend.
    private var nextBatchRecoveryAttemptAt: Double?
    /// Current backoff interval; doubles on each failed attempt, capped at
    /// `recoveryPolicy.maxRetryInterval`.
    private var currentBatchRecoveryInterval: Double = 0
    /// How the backend classified the most recent presentation failure. The
    /// recovery policy reads this instead of pattern-matching free text: a
    /// `.permanent` failure is never worth retrying, and a `.sceneContent`
    /// failure will reproduce on the same scene no matter how long we wait.
    private(set) var lastPresentationFailureKind: PresentationFailureKind?
    /// Consecutive frames the scene backend has presented since the last
    /// downgrade. The backoff ladder only restarts once this crosses
    /// ``healthySceneFrameThreshold`` — "the backend attached again" is not
    /// evidence that it works.
    private var consecutiveSuccessfulSceneFrames = 0
    /// Whether a downgrade has happened since the scene backend last proved
    /// itself. Keeps the *first* downgrade of a healthy session at the
    /// policy's initial interval instead of starting one rung up the ladder.
    private var didDowngradeSinceHealthySceneRun = false
    /// Whether the retained tree has changed since the scene-content failure
    /// that caused the current downgrade. A `.sceneContent` failure is a
    /// property of the scene, not of the device, so retrying before the tree
    /// changes only re-runs the same failure and flips the app's appearance
    /// twice for nothing.
    private var didSceneContentChangeSinceFailure = false
    /// Frames the scene backend must present before its recovery ladder is
    /// considered paid off. Half a second at 60 Hz.
    private static let healthySceneFrameThreshold = 30
    /// Test seam: lets unit tests inject a fake wall clock without touching
    /// `Win32Window.currentTimestampSeconds`.
    var recoveryClock: @MainActor () -> Double = { Win32Window.currentTimestampSeconds() }
    /// The window's monotonic frame clock. Every render entry point stamps its
    /// frame from here — including `WM_PAINT`, which used to pass `0`.
    ///
    /// The runtime's pacing gate is `timestamp > 0 && lastRenderTime > 0`, and
    /// `WM_PAINT` is the dominant path (`requestFrame` → `InvalidateRect` →
    /// `WM_PAINT`), so pacing was inert exactly where almost every frame is
    /// produced and over-strict on the timer path. Worse, the two paths
    /// disagreed about "now": one session interleaved renders at `t = 0` and
    /// `t = 523456.7`, which is only harmless while nothing but pacing reads
    /// the timestamp.
    var frameClock: @MainActor () -> Double = { Win32Window.currentTimestampSeconds() }
    /// How far below the vsync period the pacing floor sits.
    ///
    /// A floor of exactly `1/refreshRate` drops any tick that lands even
    /// microseconds early, and a timer never lands exactly on the period: at
    /// 60 Hz that halved every continuous animation to ~30 fps with
    /// alternating spacing. 1.15 admits a tick up to ~13 % early and still
    /// refuses a second frame inside the same vsync interval.
    private static let pacingIntervalTolerance = 1.15

    /// The runtime's minimum interval between rebuilds at a given refresh
    /// rate. Strictly below both the vsync period (by
    /// ``pacingIntervalTolerance``) and the animation timer's whole-millisecond
    /// cadence.
    ///
    /// The second clamp is not redundant. At 144 Hz the vsync period is
    /// 6.94 ms, the timer can only be armed for whole milliseconds so it runs
    /// at 6 ms, and a floor of `1/(144 × 1.15)` = 6.04 ms sits *above* the
    /// cadence that feeds it — every tick would arrive "too early" and the
    /// session would run at half rate for the same reason the pre-`WS-11`
    /// floor did at 60 Hz.
    static func pacingInterval(forRefreshRate refreshRate: Int) -> Double {
        let vsyncFloor = 1.0 / (Double(max(refreshRate, 1)) * pacingIntervalTolerance)
        let timerPeriod = Double(animationTimerIntervalMilliseconds(forRefreshRate: refreshRate)) / 1000.0
        return min(vsyncFloor, timerPeriod * timerCadenceJitterBudget)
    }

    /// How far below the animation timer's cadence the pacing floor sits, so
    /// a tick that lands a fraction of a millisecond early is still a frame.
    private static let timerCadenceJitterBudget = 0.9

    /// The animation timer's cadence at a given refresh rate, in whole
    /// milliseconds — the only unit `SetTimer` and `timeSetEvent` accept.
    ///
    /// Rounding was a skipped vblank every seventeenth frame: 1000/60 is
    /// 16.667 ms, `rounded()` makes that 17, and a 17 ms timer on a 60 Hz
    /// display ticks 58.8 times a second — so roughly every seventeenth vblank
    /// arrives with no frame in front of it and the animation visibly stalls
    /// for a frame. Flooring keeps the cadence strictly inside the display
    /// period, where the runtime's pacing floor refuses the extra rebuild that
    /// occasionally buys.
    static func animationTimerIntervalMilliseconds(forRefreshRate refreshRate: Int) -> UInt32 {
        let periodMilliseconds = 1000.0 / Double(max(refreshRate, 1))
        return UInt32(max(1, Int(periodMilliseconds.rounded(.down))))
    }

    /// How early a frame may arrive against its self-paced deadline and still
    /// be presented.
    ///
    /// A whole-millisecond timer cannot land on a 16.667 ms boundary. Without
    /// a tolerance the gate would defer every frame by the sub-millisecond
    /// remainder, re-arm the timer for 1 ms, and pace the window at 58.8 Hz —
    /// the same defect this group is fixing one layer up.
    private static let selfPacedEarlyTolerance = 0.0015
    private var pendingPresentation = false
    /// The runtime content revision the active presenter last put on screen,
    /// or `nil` when nothing certain is there — before the first present, and
    /// after any event that replaces the pixels underneath the bookkeeping
    /// (a presenter attach, a backend switch, a resize).
    ///
    /// This is the duplicate-present gate's memory. Measured before it
    /// existed: ~40 % of the frames presented during a hover fade were
    /// byte-identical to the previous frame — the animation timer ticked, no
    /// animated value moved far enough to dirty the tree, and the frame loop
    /// shipped the cached scene anyway because `pendingPresentation` was
    /// standing. Pixel-identical presents cost a bind, a submit, a present
    /// and (self-paced) a whole schedule slot, and buy nothing a user can
    /// see.
    private var lastPresentedContentRevision: UInt64?
    /// Presents skipped because the content revision had not moved. Surfaced
    /// in the live diagnostics so the skip is measurable, not assumed.
    private(set) var skippedIdenticalPresentCount = 0
    /// Frame-clock deadline the self-paced gate is holding the next frame to,
    /// or `0` when the display is pacing us and the gate is inert.
    private var selfPacedFrameDueAt: Double = 0
    /// One display period, as last reported by the monitor this window is on.
    /// What the backends' pacing watchdogs judge a present against.
    private var displayFrameInterval: Double = 1.0 / 60.0
    /// The interval the self-paced gate schedules frames on: one true display
    /// period.
    ///
    /// This was the runtime's pacing floor (~14.4 ms at 60 Hz) for as long as
    /// the timers underneath it ran on the default ~15.6 ms system tick — a
    /// schedule pinned to 16.667 ms rejected roughly every second tick for
    /// arriving a millisecond early and measured 49 fps on a 60 Hz display.
    /// But a floor below the period overshoots by construction: the same
    /// machine then delivered ~62 frames a second with a 13.8 ms median gap,
    /// and the frames the schedule invented were byte-identical replays the
    /// runtime's own floor refused to rebuild. The host now raises the system
    /// timer resolution to 1 ms while any animation timer runs
    /// (`Win32Window.updateTimerResolutionHold`), so the deferral wake the
    /// gate arms actually lands at its deadline and the schedule can be the
    /// display's: deadlines advance by whole periods, the long-run rate is
    /// exactly the refresh rate, and ``selfPacedEarlyTolerance`` absorbs the
    /// whole-millisecond remainder the timer still cannot express.
    private var selfPacedFrameInterval = 1.0 / 60.0
    private var startupProbeCompleted = false
    private var isWindowActive = true
    private var isWindowVisible = true
    private(set) var currentPresentationSelection: PresentationSelection?

    /// Batching flag: when true, a reload is waiting for the next native frame
    /// or cooperative main-actor turn; additional notifications are coalesced.
    private var reloadScheduled = false
    /// An accepted flush can nest through its completion callbacks. Pending
    /// maps may already be empty while that outer publication is still active.
    private var observedReloadFlushDepth = 0

    /// Set of ObjectIdentifiers for which we currently hold observation tokens.
    /// Tracked so we can match incoming change notifications to the
    /// ComponentHost's dependency set and skip rebuilds for unrelated objects.
    private struct ObservedObjectSubscription {
        let generation: UInt64
        let token: ObservationToken
    }
    private var observedObjectTokens: [ObjectIdentifier: ObservedObjectSubscription] = [:]
    private var observedObjectSubscriptionGeneration: UInt64 = 0
    /// Test registrations hold subscriptions without declaring a view dependency.
    /// Like historical registrations, they expire at the next committed root build.
    private var manuallyObservedObjectIDs: Set<ObjectIdentifier> = []

    /// Accumulates the identifiers of observable objects that triggered change
    /// notifications during the current batched window.  When the deferred
    /// reload fires, only rebuild if the ComponentHost actually depends on at
    /// least one of them.
    private var pendingChangedObjects: Set<ObjectIdentifier> = []
    /// Notifications are synchronous, but their coalesced rebuild is not.
    /// Preserve the mutation's scoped transaction until that rebuild runs.
    private struct ObservedObjectReloadContext {
        var sequence: UInt64
        var animation: (duration: Double, easing: AnimationEasing)?
        var transaction: Transaction?
    }
    private var pendingObservedObjectContexts: [ObjectIdentifier: ObservedObjectReloadContext] = [:]
    private var observedObjectChangeSequence: UInt64 = 0
    private struct ControlInvalidationContext {
        var generation: UInt64
        var animation: (duration: Double, easing: AnimationEasing)?
        var transaction: Transaction?
    }
    private var viewInvalidationGeneration: UInt64 = 0
    /// A control can invalidate during construction after its binding scope
    /// has ended. Keep its plain-binding fallback until observation filtering
    /// is safe, including when the pending objects turn out to be unrelated.
    private var pendingControlInvalidationContext: ControlInvalidationContext?

    /// Counter for reload tasks actually scheduled (not coalesced).
    /// Used for testing same-turn coalescing behavior.
    private(set) var scheduledReloadCount = 0

    /// Counter for reloads actually executed (after dependency filtering).
    /// Used for testing dependency filtering behavior.
    private(set) var executedReloadCount = 0

    /// Counter for deferred observed-object reload tasks that finished.
    /// Used for testing that deferred reload work was awaited and processed.
    private(set) var completedObservedObjectReloadTaskCount = 0

    /// Counter for deferred observed-object reload tasks that were rejected by
    /// the ComponentHost dependency set.
    private(set) var skippedObservedObjectReloadCount = 0

    /// The client size the last `WM_SIZE` reported while the window was in a
    /// modal drag, waiting for a frame to consume it.
    ///
    /// A modal size/move loop delivers `WM_SIZE` at mouse-report rate. Every
    /// one of those messages used to run a full view-tree rebuild, a UIA
    /// structure-change notification and a swap-chain `ResizeBuffers`
    /// synchronously, so a drag queued tens of frame-sized units of work per
    /// frame it could actually show and ran further behind the pointer the
    /// longer it went on. Holding the size here and applying it once, at the
    /// top of the frame the resize asks for, is what makes the work rate a
    /// function of the display rather than of the mouse.
    private var pendingLiveResizeSize: IntSize?

    /// Whether a drag has changed the tree since the last accessibility
    /// structure-change notification. A screen reader wants one notification
    /// when the window settles, not one per mouse report.
    private var owesResizeAccessibilityNotification = false

    /// Number of view-tree rebuilds the resize path has performed. Observable
    /// so a test can prove a burst of size messages inside a drag collapses
    /// into one rebuild instead of one per message.
    private(set) var executedResizeRebuildCount = 0

    /// Number of accessibility structure-change notifications the resize path
    /// has raised.
    private(set) var executedResizeAccessibilityNotificationCount = 0

    /// Counter for observed object registrations.
    /// Used for testing dependency registration tracking.
    private(set) var observedObjectRegistrationCount = 0

    /// Set of object IDs that triggered reloads (for dependency verification).
    /// Used for testing that only relevant objects trigger reloads.
    private(set) var reloadTriggeringObjectIDs: Set<ObjectIdentifier> = []

    /// Optional callback invoked when an observed object reload is scheduled.
    /// Used for testing coalescing behavior.
    var onObservedObjectReloadScheduled: ((_ changedObjectID: ObjectIdentifier, _ coalesced: Bool) -> Void)?

    /// Optional callback invoked when an observed object is registered.
    /// Used for testing dependency registration tracking.
    var onObservedObjectRegistered: ((_ objectID: ObjectIdentifier) -> Void)?

    /// Optional callback invoked when reloadContent completes.
    /// Used for testing rebuild/presentation counts.
    var onReloadContentCompleted: (() -> Void)?

    /// Optional callback invoked when a deferred observed-object reload task
    /// finishes dependency evaluation. True means its rebuild was accepted or
    /// queued; `onReloadContentCompleted` separately reports adopted content.
    var onObservedObjectReloadTaskCompleted: ((_ didReload: Bool) -> Void)?

    /// Optional callback for recording timer state changes, used for testing.
    /// Called whenever `syncAnimationDriver` updates timer configuration.
    var onTimerStateChanged: ((TimerState) -> Void)?

    /// Optional callback for recording input events after the runtime consumes them.
    /// Used by host tests to prove the real WinSwiftUIWindowHost routed converted input.
    var onInputEventRouted: ((WindowHostInputEvent) -> Void)?

    /// Invoked after a frame returns from the backend, with its CPU cost and
    /// the work that produced it. This does not acknowledge display completion;
    /// a backend recovering its device can return without presenting pixels.
    var onFramePresented: ((LiveFrameSample) -> Void)?

    /// The runtime this host drives. Exposed so a diagnostics run can read
    /// scene counters that only exist while a window is live.
    var hostedRuntime: RetainedViewRuntime {
        runtime
    }

    /// CPU elapsed time spent rebuilding since the last frame sample. A
    /// rebuild can precede the frame or run inside it when pending observed
    /// changes are flushed. The frame snapshots this counter before starting
    /// its own timer so only the earlier work is added to the frame total.
    private var pendingRebuildSeconds: Double = 0
    private var pendingRebuildCount: Int = 0
    private var isChargingRebuildCost = false
    private var pendingRebuildPhaseTimingsAvailable = true
    /// The same wall clock split into body evaluation, node construction and
    /// reconciliation, accumulated the same way.
    private var pendingComposeSeconds: Double = 0
    private var pendingNodeConstructionSeconds: Double = 0
    private var pendingReconcileSeconds: Double = 0

    /// Runs a tree rebuild, charging its cost to the next presented frame.
    /// Only clocked while a diagnostics session is listening — `frameClock()`
    /// is a QPC round-trip and this runs on every state change.
    private func chargingRebuildCost<T>(_ body: () -> T) -> T {
        guard onFramePresented != nil else {
            return body()
        }
        // Reconciliation callbacks can synchronously reload again. The outer
        // interval already contains that work; count the invocation without
        // charging its elapsed time twice. The last phase snapshot can be
        // overwritten by the nested reload, so exclude it from phase summaries.
        if isChargingRebuildCost {
            pendingRebuildPhaseTimingsAvailable = false
            let result = body()
            pendingRebuildCount += 1
            return result
        }
        isChargingRebuildCost = true
        defer { isChargingRebuildCost = false }
        let startedAt = frameClock()
        let result = body()
        pendingRebuildSeconds += frameClock() - startedAt
        pendingRebuildCount += 1
        pendingRebuildPhaseTimingsAvailable =
            pendingRebuildPhaseTimingsAvailable && runtime.collectsPhaseTimings
        pendingComposeSeconds += componentHost.lastComposeSeconds
        pendingNodeConstructionSeconds += componentHost.lastNodeConstructionSeconds
        pendingReconcileSeconds += componentHost.lastReconcileSeconds
        return result
    }

    /// A deferred epoch can release its outgoing ownership after construction
    /// has returned. Charge that work without counting another build or
    /// replaying the construction's phase measurements.
    private func chargingRebuildCleanupCost(_ cleanup: () -> Void) {
        guard onFramePresented != nil, !isChargingRebuildCost else {
            cleanup()
            return
        }
        isChargingRebuildCost = true
        defer { isChargingRebuildCost = false }
        let startedAt = frameClock()
        cleanup()
        pendingRebuildSeconds += frameClock() - startedAt
    }

    /// What the active batch backend reports about its device, or `nil` when
    /// the frame backend is presenting.
    var activeBatchBackendDiagnostics: BatchBackendDiagnostics? {
        guard activeBackend == .scene else { return nil }
        return batchRenderer?.backendDiagnostics
    }

    /// The owned batch backend can retain cancellation results after a
    /// fallback detaches it. Draining must therefore not depend on which
    /// backend currently presents, and must never start another frame.
    var gpuFrameTimingDiagnostics: GPUFrameTimingDiagnostics? {
        batchRenderer?.gpuFrameTimingDiagnostics
    }

    @discardableResult
    func setGPUFrameTimingEnabled(_ enabled: Bool) -> Bool {
        guard !enabled || !hasTornDownWindow else { return false }
        return batchRenderer?.setGPUFrameTimingEnabled(enabled) ?? false
    }

    func takeCompletedGPUFrameTimings() -> [GPUFrameTimingResult] {
        batchRenderer?.takeCompletedGPUFrameTimings() ?? []
    }

    /// Asks the active batch backend to stop pacing presents to vblank.
    /// Returns whether it honoured the request.
    @discardableResult
    func setActiveBatchBackendVSync(_ enabled: Bool) -> Bool {
        guard activeBackend == .scene, let batchRenderer else { return false }
        return batchRenderer.setPresentsWithVSync(enabled)
    }

    /// Asks the active batch backend to keep a CPU copy of every frame it
    /// presents. Returns whether it honoured the request.
    @discardableResult
    func setActiveBatchBackendFrameCapture(_ enabled: Bool) -> Bool {
        guard activeBackend == .scene, let batchRenderer else { return false }
        return batchRenderer.setCapturesPresentedFrames(enabled)
    }

    /// The pixels of the most recently presented frame, consumed.
    func takeCapturedPresentedFrame() -> BitmapSurface? {
        guard activeBackend == .scene, let batchRenderer else { return nil }
        return batchRenderer.takeCapturedPresentedFrame()
    }

    // MARK: - Diagnostics input injection
    //
    // A live diagnostics run invokes retained input directly in logical
    // coordinates, then uses the host's normal frame-request policy. This
    // bypasses the native message queue, coordinate conversion and input hook;
    // it is synthetic stress, not native input-to-present measurement.

    /// Asks for one frame, so a session has a loop to observe even when the
    /// window is idle and the animation timer is correctly stopped.
    func requestDiagnosticsFrame() {
        requestFrame(in: window)
    }

    func injectDiagnosticsPointerMove(to logicalPoint: Point) {
        guard !hasTornDownWindow else { return }
        runtime.pointerMoved(to: logicalPoint)
        commitRuntimeState(in: window, interactive: true)
    }

    func injectDiagnosticsScroll(at logicalPoint: Point, delta: Double) {
        guard !hasTornDownWindow else { return }
        runtime.mouseWheel(at: logicalPoint, delta: delta, source: .wheelNotch)
        commitRuntimeState(in: window, interactive: true)
    }

    func injectDiagnosticsClick(at logicalPoint: Point) {
        guard !hasTornDownWindow else { return }
        runtime.pointerDown(at: logicalPoint)
        guard !hasTornDownWindow else { return }
        runtime.pointerUp(at: logicalPoint)
        commitRuntimeState(in: window, interactive: true)
    }

    /// Per-window environment installed by the window coordinator. Nil for
    /// hosts created outside a coordinator (tests, single-window boots).
    var windowEnvironment: WindowSceneEnvironment?

    /// Invoked from `windowWillClose` after the host tears down its own UIA
    /// bridge; the window coordinator uses it to drop the window's record and
    /// apply the last-window-quit policy.
    var onWindowClosed: ((WinSwiftUIWindowHost) -> Void)?

    /// The Win32 window this host drives. Exposed for the window
    /// coordinator's platform hooks (start/close) and for tests.
    var platformWindow: Win32Window {
        window
    }

    var documentContext: DocumentWindowContext? { claimedDocumentContext }
    var isClosed: Bool { hasTornDownWindow }

    var canStartDocumentOperation: Bool {
        !hasTornDownWindow && !isPerformingInitialContentBuild && !componentHost.isBuilding && !reloadScheduled
            && documentContext?.owner.hasCloseCommitReservation != true
    }

    /// The injected factory must return the exact context installed before
    /// its first build. A factory that drops the copied configuration cannot
    /// turn a document request into an ordinary native window.
    func validateDocumentAdmission(expected: DocumentWindowContext?) throws {
        if let documentActivationError { throw documentActivationError }
        guard !hasTornDownWindow else { throw WindowCoordinatorError.windowClosedDuringStartup }
        if let expected {
            guard documentContext === expected, expected.host === self, expected.owner.isValid else {
                throw WindowCoordinatorError.documentContextMismatch
            }
            guard window.nativeHandle == nil else { throw WindowCoordinatorError.nativeDocumentActivationUnavailable }
        } else if configuration.isDocumentGroup || documentContext != nil {
            throw WindowCoordinatorError.documentContextMismatch
        }
    }

    /// Current timer state for observability. Updated by `syncAnimationDriver`.
    private(set) var currentTimerState: TimerState = TimerState(
        isEnabled: false,
        intervalMilliseconds: 16,
        usesHighResolution: false,
        refreshRate: 60
    )

    init(
        configuration: WindowGroupConfiguration,
        platformWindow: Win32Window? = nil,
        // Headless defaults: the CPU reference backend, which rasterizes into
        // memory and never blits. That is only acceptable because this type is
        // internal and every real window is created by
        // `WinSwiftUIWindowCoordinator`, which receives the app's resolved
        // `RenderBackendFactory` explicitly (D3D11 for the Windows product via
        // its composition root, the software presenter as the neutral
        // fallback). Nothing user-facing can reach these defaults.
        renderer: any RenderBackend = CPURenderBackendFactory().makeRenderBackend(),
        batchRenderer: (any BatchRenderBackend)? = CPURenderBackendFactory().makeBatchRenderBackend(),
        surfaceDescriptorProvider: @escaping @MainActor (Win32Window) -> SurfaceDescriptor? = WinSwiftUIWindowHost
            .defaultSurfaceDescriptor,
        sceneRenderer: (@MainActor (RetainedViewRuntime, Double) -> GPUIScene)? = nil,
        startupPresentationMode: StartupPresentationMode = .fromEnvironment(),
        startupProbeConfiguration: StartupProbeConfiguration? = .fromEnvironment(),
        recoveryPolicy: BatchBackendRecoveryPolicy = .standard,
        backendResolution: RenderBackendResolution? = nil,
        presentPacingMemory: PresentPacingMemoryStore? = nil
    ) {
        var configuration = configuration
        if !configuration.isDocumentGroup {
            configuration.instantiateWindowContent()
        }
        self.backendResolution = backendResolution
        self.presentPacingMemory = presentPacingMemory
        self.configuration = configuration
        if let context = configuration.documentWindowContext {
            self.undoManager = context.undoManager
            self.windowEnvironment = context.environment
        } else {
            self.undoManager = UndoManager()
        }
        self.window =
            platformWindow
            ?? Win32Window(
                title: configuration.title,
                clientSize: WinSwiftUIWindowHost.initialClientSize(for: configuration),
                titleBarVisibility: configuration.titleBarVisibility ?? .automatic,
                configuration: WinSwiftUIWindowHost.platformConfiguration(for: configuration))
        self.renderer = renderer
        self.batchRenderer = batchRenderer
        self.surfaceDescriptorProvider = surfaceDescriptorProvider
        self.runtime = RetainedViewRuntime(clearColor: configuration.clearColor, root: ViewNode())
        self.componentHost = ComponentHost(runtime: runtime)
        self.sceneRenderer =
            sceneRenderer ?? { runtime, timestamp in
                runtime.renderScene(at: timestamp)
            }
        self.startupPresentationMode = startupPresentationMode
        self.startupProbeConfiguration = startupProbeConfiguration
        self.recoveryPolicy = recoveryPolicy
        self.currentBatchRecoveryInterval = recoveryPolicy.initialRetryInterval

        // A bare legacy document marker remains an unadapted raw host. Typed
        // document metadata must claim its exact prepared context; neither
        // path permits native document activation.
        if configuration.documentScene != nil || configuration.documentWindowContext != nil {
            guard configuration.isDocumentGroup,
                let descriptor = configuration.documentScene,
                let context = configuration.documentWindowContext,
                context.descriptor.id == descriptor.id,
                context.owner.isValid, context.host == nil,
                window.nativeHandle == nil
            else {
                documentActivationError = WindowCoordinatorError.nativeDocumentActivationUnavailable
                isPerformingInitialContentBuild = false
                windowWillClose(window)
                return
            }
            claimedDocumentContext = context
            context.bind(
                host: self, runtime: runtime,
                dialogOwner: { [weak window] in .hostedWindow(window) },
                invalidate: { [weak self] in self?.reloadContentFromView() }
            )
        }

        runtime.setRootSize(WinSwiftUIWindowHost.initialClientSize(for: configuration))
        componentHost.fileDialogOwner = { [weak window] in
            .hostedWindow(window)
        }
        componentHost.buildLifecycle = stateMountCoordinator
        windowCloseRegistration = window.installCloseAuthority(self)
        componentHost.measureBuild = { [weak self] build in
            guard let self else {
                build()
                return
            }
            if !self.isPerformingInitialContentBuild {
                self.executedReloadCount += 1
            }
            self.chargingRebuildCost(build)
        }
        componentHost.measureBuildCleanup = { [weak self] cleanup in
            guard let self else {
                cleanup()
                return
            }
            self.chargingRebuildCleanupCost(cleanup)
        }
        componentHost.setComponents { [weak self] in
            guard let self else {
                return []
            }

            return [self.buildRootComponent()]
        }
        isPerformingInitialContentBuild = false
        guard !hasTornDownWindow, documentContext?.owner.isValid != false else {
            documentActivationError = WindowCoordinatorError.windowClosedDuringStartup
            windowWillClose(window)
            return
        }
        window.delegate = self
        syncWindowDismissBehavior()

        // UI Automation wiring: the bridge re-projects the retained tree on
        // every UIA query; focus events ride the runtime's focus hook.
        let uiaTreeSource = RuntimeUIAElementTreeSource(runtime: runtime) { [weak window] bounds in
            window?.clientRectToScreen(bounds) ?? bounds
        }
        let uiaBridge = UIAProviderBridge(source: uiaTreeSource)
        window.accessibilityProvider = uiaBridge
        self.uiaTreeSource = uiaTreeSource
        self.uiaBridge = uiaBridge
        runtime.onAccessibilityFocusChanged = { [weak self] node in
            self?.accessibilityFocusDidChange(to: node)
        }
    }

    isolated deinit {
        if !hasTornDownWindow {
            hasTornDownWindow = true
            documentContext?.owner.revoke()
            let closeWorkPin = windowCloseRegistration?.pinDeferredWork()
            let closingParticipant = windowCloseParticipant
            let closeBuildWait = pendingCloseBuildWait
            defer { withExtendedLifetime((closeWorkPin, closingParticipant, closeBuildWait)) {} }
            closeParticipantIdentity = CloseParticipantIdentity()
            windowCloseParticipant = nil
            closeBuildWait?.isValid = false
            closeBuildWait?.isWaiting = false
            closeBuildWait?.coordinatorObserverPending = false
            pendingCloseBuildWait = nil
            closePreflight?.hasFinished = true
            closeCommitReservation = nil
            windowCloseRegistration?.revoke()
            closingParticipant?.revokeCloseParticipation()
            componentHost.invalidateFileDialogRequests()
            runtime.stopRenderLifecycleCallbacks()
            let textInputTeardown = prepareTextInputUndoForWindowClose(in: runtime)
            stateMountCoordinator.close()
            documentContext?.invalidate()
            textInputTeardown.purgeHistory()
            runtime.cancelRenderLifecycleTasks()
            textInputTeardown.detach()
        }
    }

    // MARK: - Window configuration
    //
    // The scene modifiers have always parsed `minSize` / `maxSize` /
    // `idealSize` / `defaultPosition` / `resizability` / `windowLevel` into
    // `WindowGroupConfiguration` and then dropped them: nothing between the
    // configuration and `CreateWindowExW` read a single one. These three
    // members are the whole translation — what the Win32 host can enforce, and
    // an explicit list of what it cannot, so an unsupported modifier is
    // reported once instead of silently doing nothing.

    /// Client size the window opens at, in logical points. `idealSize` is
    /// SwiftUI's "open at this size" knob (`.defaultSize`), so it wins over
    /// the group's declared size, clamped into any min/max the app also set.
    static func initialClientSize(for configuration: WindowGroupConfiguration) -> IntSize {
        var size = configuration.idealSize ?? configuration.size
        if let minimum = configuration.minSize {
            size = IntSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
        }
        if let maximum = configuration.maxSize {
            size = IntSize(width: min(size.width, maximum.width), height: min(size.height, maximum.height))
        }
        return size
    }

    static func platformConfiguration(for configuration: WindowGroupConfiguration) -> Win32WindowConfiguration {
        // `.contentSize` pins the window to its content; `.minSize` and
        // `.maxSize` stay resizable and are expressed through the track-size
        // limits below, which is as close as Win32 gets to them.
        let resizability: Win32WindowConfiguration.Resizability =
            configuration.resizability?.kind == .contentSize ? .fixedSize : .resizable

        let isAlwaysOnTop: Bool
        switch configuration.windowLevel?.kind {
        case .floating, .tornOffMenu, .modalPanel, .mainMenu, .statusBar, .popUpMenu, .screenSaver, .overlay:
            isAlwaysOnTop = true
        case .normal, .base, nil:
            isAlwaysOnTop = false
        }

        return Win32WindowConfiguration(
            minimumClientSize: configuration.minSize,
            maximumClientSize: configuration.maxSize,
            normalizedPosition: configuration.defaultPosition.map {
                Point(x: $0.position.x, y: $0.position.y)
            },
            resizability: resizability,
            isAlwaysOnTop: isAlwaysOnTop
        )
    }

    /// Preserves every supported scene/window modifier when the composition
    /// root delegates native window creation to its platform factory.
    static func platformWindowConfiguration(
        for configuration: WindowGroupConfiguration
    ) -> PlatformWindowConfiguration {
        let nativeConfiguration = platformConfiguration(for: configuration)
        return PlatformWindowConfiguration(
            title: configuration.title,
            clientSize: initialClientSize(for: configuration),
            titleBarVisibility: configuration.titleBarVisibility ?? .automatic,
            minimumClientSize: nativeConfiguration.minimumClientSize,
            maximumClientSize: nativeConfiguration.maximumClientSize,
            normalizedPosition: nativeConfiguration.normalizedPosition,
            isResizable: nativeConfiguration.resizability == .resizable,
            isAlwaysOnTop: nativeConfiguration.isAlwaysOnTop
        )
    }

    /// Scene modifiers this window parsed but cannot honour on Win32.
    /// Reported once at creation: a modifier that does nothing is a bug
    /// report waiting to happen, and silence is the worst possible answer.
    var unsupportedWindowConfigurationModifiers: [String] {
        var unsupported: [String] = []
        func note(_ name: String, _ isSet: Bool) {
            if isSet {
                unsupported.append(name)
            }
        }

        note("windowToolbarStyle", configuration.toolbarStyle != nil)
        note("menuBarExtraStyle", configuration.menuBarExtraStyle != nil)
        note("windowStyle", configuration.windowStyle != nil)
        note("restorationBehavior", configuration.restorationBehavior != nil)
        note("defaultLaunchBehavior", configuration.launchBehavior != nil)
        note("windowActivationMode", configuration.activationMode != nil)
        note("windowBackgroundDragBehavior", configuration.backgroundDragBehavior != nil)
        note("navigationSubtitle", configuration.subtitle != nil)
        note("persistentSystemOverlays", configuration.persistenceBehavior != nil)
        note("windowManagerRole", configuration.windowManagerRole != nil)
        note("allowsWindowInlining", configuration.allowsWindowInlining != nil)
        return unsupported
    }

    private func reportUnsupportedWindowConfigurationIfNeeded() {
        let unsupported = unsupportedWindowConfigurationModifiers
        guard !unsupported.isEmpty else {
            return
        }

        report(
            "Window \"\(configuration.title)\" declares scene modifiers this host does not apply: "
                + unsupported.joined(separator: ", ")
                + ". See docs/CompatibilityStatus.md."
        )
    }

    private func accessibilityFocusDidChange(to node: ViewNode?) {
        // Skip re-projection entirely when no assistive client is attached.
        guard let uiaBridge, uiaBridge.isClientListening else {
            return
        }
        guard let node, let elementID = uiaTreeSource?.projectedElementID(forNodeOrAncestor: node) else {
            return
        }
        uiaBridge.raiseFocusChanged(elementID: elementID)
    }

    @discardableResult
    func run() throws -> Int32 {
        try validateNativeActivation()
        return try Win32Application.run(window: window)
    }

    /// A non-creating preflight shared by direct run and headless assertions.
    /// Tests must not call the native message loop to prove a rejection: a
    /// regression of that rejection would otherwise open UI or block them.
    func validateNativeActivation() throws {
        if configuration.isDocumentGroup || configuration.documentScene != nil
            || configuration.documentWindowContext != nil
        {
            throw WindowCoordinatorError.nativeDocumentActivationUnavailable
        }
        if let documentActivationError { throw documentActivationError }
        guard !hasTornDownWindow else { throw WindowCoordinatorError.windowClosedDuringStartup }
    }

    func windowDidCreate(_ window: Win32Window) {
        guard !hasTornDownWindow else { return }
        syncWindowDismissBehavior()
        reportUnsupportedWindowConfigurationIfNeeded()
        do {
            guard let surface = surfaceDescriptorProvider(window) else {
                recordPresenterAttachFailure("Missing surface descriptor.", in: window)
                completeStartupProbeIfNeeded(in: window, success: false, errorMessage: "Missing surface descriptor.")
                return
            }

            try activatePresenter(with: surface)
            let didRender = renderCurrentFrame(in: window)
            completeStartupProbeIfNeeded(
                in: window,
                success: didRender,
                errorMessage: didRender ? nil : "Initial startup render did not complete."
            )
        } catch {
            recordPresenterAttachFailure(String(describing: error), in: window)
            completeStartupProbeIfNeeded(in: window, success: false, errorMessage: String(describing: error))
            report(error)
        }
    }

    /// Binds a surface to a backend and brings the window's runtime state up
    /// to match it. Shared by the startup attach and by the bounded retry, so
    /// a window that recovers a presenter is in exactly the state a window
    /// that never lost one is.
    private func activatePresenter(with surface: SurfaceDescriptor) throws {
        guard !hasTornDownWindow else { return }
        surfaceDescriptor = surface
        try attachPreferredRenderer(to: surface)
        // A freshly attached backend has never been told what it is presenting
        // to, and its pacing watchdog cannot judge a present against a display
        // period it does not have.
        applyDisplayFrameInterval(displayFrameInterval, force: true)
        isRendererReady = true
        isPresenterUnavailable = false
        presenterAttachAttemptCount = 0
        nextPresenterAttachAttemptAt = nil
        invalidatePresentedContentTracking()
        seedPresentPacingFromMemoryIfRemembered()
        let scaleFactor = Win32Window.effectiveScaleFactor(for: surface.scaleFactor)
        runtime.displayScale = scaleFactor
        // Claim, not assign: with a second window open this host's scale is not
        // the process's answer. See `claimDefaultIconDisplayScale`.
        NativeTextRenderer.claimDefaultIconDisplayScale(scaleFactor, owner: self)
        runtime.setRootSize(logicalSize(for: surface))
        componentHost.reload()
        syncWindowDismissBehavior()
        uiaBridge?.raiseStructureChanged()
    }

    /// Records that the window currently has no presenter and either schedules
    /// the next bounded retry or enters the terminal state.
    private func recordPresenterAttachFailure(_ detail: String, in window: Win32Window) {
        isRendererReady = false
        lastPresenterAttachFailureDetail = detail
        reportRepeating("No render backend is attached. \(detail)", signature: "presenter-attach-failure")

        guard presenterAttachAttemptCount < Self.maximumPresenterAttachAttempts else {
            enterPresenterUnavailableState(in: window)
            return
        }

        let backoff = min(
            Self.initialPresenterAttachRetryInterval * pow(2, Double(presenterAttachAttemptCount)),
            Self.maximumPresenterAttachRetryInterval
        )
        nextPresenterAttachAttemptAt = recoveryClock() + backoff
        syncAnimationDriver(for: window)
    }

    /// Terminal no-presenter state: stop requesting frames entirely and make
    /// the reason observable. Anything else burns a core drawing nothing.
    private func enterPresenterUnavailableState(in window: Win32Window) {
        isPresenterUnavailable = true
        isRendererReady = false
        nextPresenterAttachAttemptAt = nil
        pendingPresentation = false
        activeBackend = .frame
        updatePresentationSelection(reason: .presenterUnavailable(lastPresenterAttachFailureDetail))
        report(
            "No render backend could be attached after \(presenterAttachAttemptCount) attempts. "
                + "The window will stop requesting frames; see RendererHealthSnapshot.isPresenterUnavailable. "
                + lastPresenterAttachFailureDetail
        )
        syncAnimationDriver(for: window)
    }

    /// Retries the attach when the backoff has elapsed. Returns `true` when a
    /// presenter is attached and this frame may proceed.
    @discardableResult
    private func attemptPresenterAttachRetryIfDue(in window: Win32Window) -> Bool {
        guard !hasTornDownWindow, !isRendererReady,
            !isPresenterUnavailable,
            let dueAt = nextPresenterAttachAttemptAt,
            recoveryClock() >= dueAt
        else {
            return false
        }

        guard let surface = surfaceDescriptorProvider(window) else {
            nextPresenterAttachAttemptAt = nil
            presenterAttachAttemptCount += 1
            recordPresenterAttachFailure("Missing surface descriptor.", in: window)
            return false
        }

        // A minimized window reports a 0×0 client rect — `Win32Window` keeps
        // that cache truthful rather than frozen at the pre-minimize size — and
        // no backend can build a swap chain for it. That is a window state, not
        // a graphics failure, so it defers the attempt instead of spending one
        // of the five that end in the terminal no-presenter state.
        guard surface.pixelSize.width > 0, surface.pixelSize.height > 0 else {
            nextPresenterAttachAttemptAt = recoveryClock() + Self.initialPresenterAttachRetryInterval
            return false
        }

        nextPresenterAttachAttemptAt = nil
        presenterAttachAttemptCount += 1
        let attempt = presenterAttachAttemptCount

        do {
            try activatePresenter(with: surface)
            resetFailureReporting()
            report("Render backend attached after \(attempt) retry attempt(s).")
            return true
        } catch {
            recordPresenterAttachFailure(String(describing: error), in: window)
            return false
        }
    }

    func window(_ window: Win32Window, didResizeTo size: IntSize) {
        guard !hasTornDownWindow else { return }
        // An empty client rect is not a layout. Minimizing used to rebuild the
        // whole component tree at 0×0 — through collapsed-frame layout, a UIA
        // structure change and a renderer resize — and then do it all again on
        // restore. The wndproc filters `SIZE_MINIMIZED`; this is the backstop
        // for every other source of an empty rect.
        guard size.width > 0, size.height > 0 else {
            return
        }

        // Inside a modal drag the same handler was doing a frame's worth of
        // work per mouse report. Record the newest size, ask for a frame, and
        // let the frame apply it: intermediate sizes the display never showed
        // cost one assignment each instead of a rebuild, a UIA notification
        // and a `ResizeBuffers`. The pump that consumes it is guaranteed —
        // `requestFrame` both invalidates the window and enables the
        // animation timer, and the modal loop runs that timer at
        // `USER_TIMER_MINIMUM`.
        if window.isInLiveResize {
            pendingLiveResizeSize = size
            requestFrame(in: window)
            return
        }

        applyResize(size, in: window, requestsFrame: true)
    }

    /// Applies a client size to the runtime, the surface descriptor and the
    /// active renderer.
    ///
    /// - Parameter requestsFrame: false when the caller is already inside the
    ///   frame this resize is for. `requestFrame` calls `InvalidateRect`, and
    ///   doing that from inside `WM_PAINT`'s BeginPaint/EndPaint pair
    ///   re-dirties the region the paint just validated — the window spins.
    private func applyResize(_ size: IntSize, in window: Win32Window, requestsFrame: Bool) {
        guard !hasTornDownWindow else { return }
        // Whatever the drag left behind is superseded by this size, including
        // when this call *is* the drag's final `WM_EXITSIZEMOVE` delivery.
        // Without this the next frame would rebuild a second time for a size
        // the window already has.
        pendingLiveResizeSize = nil

        do {
            let scaleFactor = window.effectiveScaleFactor
            runtime.displayScale = scaleFactor
            // A resize can be a DPI change (monitor move), so the sole-window
            // claim is refreshed here too — and refused just the same once a
            // second window is live.
            NativeTextRenderer.claimDefaultIconDisplayScale(scaleFactor, owner: self)
            surfaceDescriptor?.pixelSize = size
            surfaceDescriptor?.scaleFactor = scaleFactor
            runtime.setRootSize(logicalSize(for: size, scaleFactor: scaleFactor))
            componentHost.reload()
            syncWindowDismissBehavior()
            executedResizeRebuildCount += 1

            // A drag is one structural event, not a hundred. The bridge
            // re-projects the whole retained tree on every query, so telling a
            // screen reader the structure changed on each mouse report is both
            // useless to it and expensive here; the notification is owed until
            // the window settles.
            if window.isInLiveResize {
                owesResizeAccessibilityNotification = true
            } else {
                owesResizeAccessibilityNotification = false
                uiaBridge?.raiseStructureChanged()
                executedResizeAccessibilityNotificationCount += 1
            }

            try resizeActiveRenderer(to: size, in: window)

            if requestsFrame {
                requestFrame(in: window)
            }
        } catch {
            report(error)
        }
    }

    /// Consumes the size a drag left behind, at the top of the frame that
    /// drag asked for. Returns whether anything was applied.
    @discardableResult
    private func applyPendingLiveResizeIfNeeded(in window: Win32Window) -> Bool {
        guard let pending = pendingLiveResizeSize else {
            // The drag ended without another `WM_SIZE` carrying a new size
            // (the pointer came back to where it started). The structure
            // notification is still owed.
            flushDeferredResizeAccessibilityNotificationIfNeeded(in: window)
            return false
        }

        pendingLiveResizeSize = nil
        applyResize(pending, in: window, requestsFrame: false)
        flushDeferredResizeAccessibilityNotificationIfNeeded(in: window)
        return true
    }

    private func flushDeferredResizeAccessibilityNotificationIfNeeded(in window: Win32Window) {
        guard owesResizeAccessibilityNotification, !window.isInLiveResize else {
            return
        }

        owesResizeAccessibilityNotification = false
        uiaBridge?.raiseStructureChanged()
        executedResizeAccessibilityNotificationCount += 1
    }

    func windowNeedsDisplay(_ window: Win32Window) {
        _ = renderCurrentFrame(in: window)
    }

    func window(_ window: Win32Window, pointerMovedTo point: Point) {
        guard !hasTornDownWindow else { return }
        let scaleFactor = window.effectiveScaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerMoved(to: logicalPoint)
        onInputEventRouted?(.pointerMoved(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func windowPointerDidLeave(_ window: Win32Window) {
        guard !hasTornDownWindow else { return }
        runtime.pointerExitedWindow()
        onInputEventRouted?(.pointerExitedWindow)
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {
        self.window(window, mouseWheelAt: point, delta: delta, source: .wheelNotch)
    }

    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double, source: ScrollInputSource) {
        guard !hasTornDownWindow else { return }
        let scaleFactor = window.effectiveScaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.mouseWheel(at: logicalPoint, delta: delta, source: source)
        onInputEventRouted?(.mouseWheel(point: logicalPoint, delta: delta, axis: nil, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, horizontalScrollAt point: Point, delta: Double) {
        self.window(window, horizontalScrollAt: point, delta: delta, source: .wheelNotch)
    }

    func window(
        _ window: Win32Window, horizontalScrollAt point: Point, delta: Double, source: ScrollInputSource
    ) {
        guard !hasTornDownWindow else { return }
        let scaleFactor = window.effectiveScaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.mouseWheel(at: logicalPoint, delta: delta, axis: .horizontal, source: source)
        onInputEventRouted?(.mouseWheel(point: logicalPoint, delta: delta, axis: .horizontal, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        guard !hasTornDownWindow else { return }
        let scaleFactor = window.effectiveScaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerDown(at: logicalPoint)
        onInputEventRouted?(.pointerDown(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        guard !hasTornDownWindow else { return }
        let scaleFactor = window.effectiveScaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerUp(at: logicalPoint)
        onInputEventRouted?(.pointerUp(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, touchBegan points: [Point]) {
        guard !hasTornDownWindow, !isPrimaryTouchActive, let point = points.first else {
            return
        }

        isPrimaryTouchActive = true
        self.window(window, leftMouseDownAt: point)
    }

    func window(_ window: Win32Window, touchMoved points: [Point]) {
        guard !hasTornDownWindow, isPrimaryTouchActive, let point = points.first else {
            return
        }

        self.window(window, pointerMovedTo: point)
    }

    func window(_ window: Win32Window, touchEnded points: [Point]) {
        guard !hasTornDownWindow, isPrimaryTouchActive, let point = points.first else {
            return
        }

        isPrimaryTouchActive = false
        self.window(window, leftMouseUpAt: point)
    }

    func windowDidCancelPointerInteraction(_ window: Win32Window) {
        guard !hasTornDownWindow else { return }
        isPrimaryTouchActive = false
        runtime.pointerCancelled()
        onInputEventRouted?(.pointerCancelled)
        commitRuntimeState(in: window, interactive: true)
    }

    func windowDidReceiveRightClick(_ window: Win32Window, event: MouseEvent) {
        guard !hasTornDownWindow else { return }
        let scaleFactor = window.effectiveScaleFactor
        let logicalPoint = logicalPoint(event.position, scaleFactor: scaleFactor)
        runtime.contextClick(at: logicalPoint)
        onInputEventRouted?(.contextClick(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, imeComposition event: IMECompositionEvent) {
        guard !hasTornDownWindow else { return }
        runtime.imeComposition(event)
        commitRuntimeState(in: window, interactive: true)
    }

    func windowTextInputCaretRect(_ window: Win32Window) -> Rect? {
        guard !hasTornDownWindow else { return nil }
        return runtime.focusedTextInputCaretRect
    }

    func window(_ window: Win32Window, didReceiveFileDrop payload: FileDropPayload) {
        guard !hasTornDownWindow else { return }
        let logicalPoint = logicalPoint(payload.clientPoint, scaleFactor: window.effectiveScaleFactor)
        _ = runtime.performFileDrop(payload.fileURLs, at: logicalPoint)
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
        guard !hasTornDownWindow else { return }
        runtime.keyDown(event)
        onInputEventRouted?(.keyDown(event))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, didInputText text: String) {
        guard !hasTornDownWindow, !text.isEmpty else {
            return
        }

        // The existing composition-commit path already replaces selections,
        // updates caret chrome, supports secure fields, and rejects newlines
        // in single-line controls. Tagging the source preserves the keyboard
        // autocapitalization rules without altering genuine IME results.
        runtime.imeComposition(IMECompositionEvent(phase: .committed(text), source: .keyboard))
        onInputEventRouted?(.textInput(text))
        commitRuntimeState(in: window, interactive: true)
    }

    func windowDidLoseKeyboardFocus(_ window: Win32Window) {
        guard !hasTornDownWindow else { return }
        if isPrimaryTouchActive {
            isPrimaryTouchActive = false
            runtime.pointerCancelled()
            onInputEventRouted?(.pointerCancelled)
        }
        runtime.keyboardFocusDidLeaveWindow()
        onInputEventRouted?(.keyboardFocusDidLeaveWindow)
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, animationFrameAt timestamp: Double) {
        guard !hasTornDownWindow else { return }
        guard isRendererReady else {
            // While no presenter is attached the timer runs only to drive the
            // bounded attach retry: there is nothing to tick and nothing to
            // paint until a backend owns the swap chain.
            if attemptPresenterAttachRetryIfDue(in: window) {
                _ = renderCurrentFrame(in: window, timestamp: timestamp)
            } else {
                syncAnimationDriver(for: window)
            }
            return
        }

        _ = renderCurrentFrame(in: window, timestamp: timestamp)
    }

    func windowDidChangeDisplay(_ window: Win32Window) {
        syncAnimationDriver(for: window)
        // The verdict is filed per display; the one in front of the window
        // now is not the one the key described. The watchdog itself probes
        // immediately on the interval change (`setDisplayFrameInterval`), and
        // whatever it concludes is re-filed under the new key.
        if presentPacingMemory != nil, isRendererReady {
            presentPacingMemoryKey = computePresentPacingMemoryKey()
            lastPersistedPacingVerdict = nil
        }
    }

    func windowDidChangeSystemSettings(_ window: Win32Window) {
        syncAnimationDriver(for: window)
        // The system appearance snapshot was invalidated by the host; rebuild
        // so high-contrast / theme changes apply without an app restart.
        if isRendererReady {
            reloadContent()
        }
    }

    func windowDidChangeActiveState(_ window: Win32Window, isActive: Bool) {
        guard isWindowActive != isActive else {
            return
        }

        isWindowActive = isActive
        if isRendererReady {
            reloadContent()
        }
    }

    func windowDidChangeVisibility(_ window: Win32Window, isVisible: Bool) {
        guard isWindowVisible != isVisible else {
            return
        }

        isWindowVisible = isVisible
        if isRendererReady {
            reloadContent()
        }
    }

    func windowShouldClose(_ window: Win32Window) -> Bool {
        guard window === self.window else { return false }
        if let attempt = window.activeCloseAttempt {
            return evaluateNativeClosePreflight(attempt)
        }
        guard
            !configuration.isDocumentGroup || windowCloseParticipant != nil
                || (documentContext != nil && window.nativeHandle == nil)
        else { return false }
        // Direct Bool queries remain useful for headless coordinator hooks.
        // They do not mint a native receipt or authorize a later destruction.
        guard !isEvaluatingWindowClosePolicy else { return false }
        isEvaluatingWindowClosePolicy = true
        defer { isEvaluatingWindowClosePolicy = false }
        guard !isPerformingInitialContentBuild, !componentHost.isBuilding else { return false }
        // A state write and a close can share one native message turn. Consume
        // the pending observed-object rebuild before reading its policy.
        if !hasTornDownWindow {
            flushObservedObjectReload(in: window, requestsFrame: false)
        }
        syncWindowDismissBehavior()
        // Rebuild completion can mutate another observed value or pump a
        // native dialog. Do not approve using a tree already due for rebuild,
        // or spin here waiting for arbitrary application callbacks to settle.
        if let documentContext {
            guard !hasTornDownWindow else { return false }
            _ = documentContext.session.requestClose(isHostSettled: isDocumentCloseSettled)
            // This session is not adapted to native final close participation.
            // Even a clean headless approval needs an explicit commit below;
            // this Boolean query must never authorize document destruction.
            return false
        }
        return hasTornDownWindow || (!reloadScheduled && window.isCloseButtonEnabled)
    }

    /// Replacing a session retires its tickets without removing this host's
    /// mandatory final authority. A final reservation cannot be displaced.
    @discardableResult
    func setWindowCloseParticipant(_ participant: (any WindowCloseParticipant)?) -> Bool {
        guard !hasTornDownWindow, closeCommitReservation == nil, !isReplacingWindowCloseParticipant else {
            return false
        }
        guard windowCloseParticipant !== participant else { return true }
        isReplacingWindowCloseParticipant = true
        defer { isReplacingWindowCloseParticipant = false }
        let previous = windowCloseParticipant
        let workPin = windowCloseRegistration?.pinDeferredWork()
        let previousBuildWait = pendingCloseBuildWait
        let nextIdentity = CloseParticipantIdentity()
        closeParticipantIdentity = nextIdentity
        windowCloseParticipant = participant
        previousBuildWait?.isValid = false
        previousBuildWait?.isWaiting = false
        previousBuildWait?.coordinatorObserverPending = false
        pendingCloseBuildWait = nil
        windowCloseRegistration?.invalidateTickets()
        previous?.revokeCloseParticipation()
        // Keep an in-flight preflight record: a later concrete vote in this
        // same attempt must reject its old slot, never capture the new one.
        return withExtendedLifetime((previous, workPin, previousBuildWait)) {
            !hasTornDownWindow && closeParticipantIdentity === nextIdentity
        }
    }

    /// Enqueue one owned native wake, or wait for pending host reload work and
    /// coordinated builds to settle before posting it. The wake is not a close approval:
    /// its action must validate the current intent and perform fresh preflight.
    /// Both closures must capture their host/session weakly. Failure delivery
    /// may publish framework state only; it must not prompt, close, or retry
    /// inline. Immediate submission failures are returned, never also reported
    /// to the callback. A failure after waiting is reported exactly once.
    func enqueueCloseWork(
        ticket: Win32CloseTicket, for participant: any WindowCloseParticipant, phase: Win32DeferredClosePhase,
        onSubmissionFailure: @escaping @MainActor (Win32CloseTicket, Win32DeferredCloseSubmission) -> Void,
        action: @escaping @MainActor (Win32CloseTicket) -> Void
    ) -> WindowCloseWorkSubmission {
        guard !isSubmittingWindowCloseWork, closeCommitReservation == nil else { return .busy }
        guard !hasTornDownWindow, !isReplacingWindowCloseParticipant,
            windowCloseParticipant === participant, let registration = windowCloseRegistration,
            registration.isCurrent, ticket.isCurrent,
            componentHost.buildLifecycle === stateMountCoordinator
        else { return .unavailable }
        isSubmittingWindowCloseWork = true
        defer { isSubmittingWindowCloseWork = false }

        var retiredWait: CloseBuildWait?
        defer { withExtendedLifetime(retiredWait) {} }
        if let pending = pendingCloseBuildWait {
            if isCloseWorkCurrent(pending, participant: participant) {
                return pending.ticket === ticket && pending.phase == phase ? .coalesced : .busy
            }
            pending.isValid = false
            pending.isWaiting = false
            pending.coordinatorObserverPending = false
            retiredWait = pending
            pendingCloseBuildWait = nil
        }
        guard pendingLiveResizeSize == nil else { return .unavailable }
        if case .unavailable = runtime.layoutSettlementStatus { return .unavailable }

        let wait = CloseBuildWait(
            ticket: ticket, phase: phase, registration: registration,
            participantIdentity: closeParticipantIdentity, participant: participant,
            onSubmissionFailure: onSubmissionFailure, action: action)
        if !hasPendingCloseHostWork, componentHost.isBuildSettled {
            let submission = postCloseWork(wait, participant: participant)
            if submission != .queued, submission != .coalesced { wait.isValid = false }
            return WindowCloseWorkSubmission(submission)
        }

        wait.isWaiting = true
        wait.isRegistering = true
        pendingCloseBuildWait = wait
        // An idle coordinator cannot announce a host-only observed batch.
        // Park that batch for its existing flush, without an idle observer.
        let accepted = componentHost.isBuildSettled || observeCoordinatorForCloseBuildWait(wait)
        wait.isRegistering = false
        guard accepted else {
            wait.isValid = false
            wait.isWaiting = false
            wait.coordinatorObserverPending = false
            if pendingCloseBuildWait === wait { pendingCloseBuildWait = nil }
            return .unavailable
        }
        // The coordinator may finish during registration. Report such a
        // synchronous post failure to this caller, not twice through both
        // the return value and the deferred failure callback.
        if let submission = wait.submission { return WindowCloseWorkSubmission(submission) }
        return .waitingForBuilds
    }

    private var hasPendingCloseHostWork: Bool {
        isPerformingInitialContentBuild || observedReloadFlushDepth != 0 || reloadScheduled
            || !pendingChangedObjects.isEmpty || !pendingObservedObjectContexts.isEmpty
            || pendingControlInvalidationContext != nil
    }

    /// Called only for actual unsettled component work. A consumed observer
    /// never registers itself again; host-only work waits for a real flush.
    private func observeCoordinatorForCloseBuildWait(_ wait: CloseBuildWait) -> Bool {
        guard pendingCloseBuildWait === wait, wait.isWaiting, wait.isValid else { return false }
        guard !wait.coordinatorObserverPending, !componentHost.isBuildSettled else { return true }
        wait.coordinatorObserverPending = true
        let accepted = componentHost.scheduleAfterBuildsSettled(owner: wait) { [weak self, weak wait] in
            guard let self, let wait, wait.coordinatorObserverPending else { return }
            wait.coordinatorObserverPending = false
            self.resumeCloseBuildWait(wait)
        }
        if !accepted { wait.coordinatorObserverPending = false }
        return accepted
    }

    /// Only an accepted outermost observed flush calls this, after it has
    /// published pending state and restored its transaction. It does not
    /// manufacture layout, a frame, or another observation notification.
    private func observedReloadFlushDidComplete() {
        guard let wait = pendingCloseBuildWait, wait.isWaiting else { return }
        resumeCloseBuildWait(wait)
        guard pendingCloseBuildWait === wait, wait.isWaiting,
            !wait.coordinatorObserverPending, !componentHost.isBuildSettled
        else { return }
        if !observeCoordinatorForCloseBuildWait(wait), let participant = wait.participant {
            completeCloseBuildWait(wait, participant: participant, submission: .unavailable)
        }
    }

    private func isCloseWorkCurrent(_ wait: CloseBuildWait, participant: any WindowCloseParticipant) -> Bool {
        wait.isValid && !hasTornDownWindow && closeCommitReservation == nil
            && windowCloseParticipant === participant && wait.participant === participant
            && closeParticipantIdentity === wait.participantIdentity
            && windowCloseRegistration === wait.registration && wait.registration.isCurrent && wait.ticket.isCurrent
    }

    private func postCloseWork(
        _ wait: CloseBuildWait, participant: any WindowCloseParticipant
    ) -> Win32DeferredCloseSubmission {
        guard isCloseWorkCurrent(wait, participant: participant) else { return .unavailable }
        return withExtendedLifetime(participant) {
            wait.registration.enqueue(
                ticket: wait.ticket, phase: wait.phase,
                onPostFailure: { [weak self, weak participant, wait] ticket, code in
                    guard let self, let participant, ticket === wait.ticket else { return }
                    self.publishCloseWorkFailure(wait, participant: participant, submission: .postFailed(code))
                },
                action: { [weak self, weak participant, wait] ticket in
                    guard let self, let participant, ticket === wait.ticket,
                        self.isCloseWorkCurrent(wait, participant: participant)
                    else { return }
                    withExtendedLifetime((self, participant, wait)) { wait.action(ticket) }
                })
        }
    }

    private func resumeCloseBuildWait(_ wait: CloseBuildWait) {
        guard pendingCloseBuildWait === wait, wait.isWaiting else { return }
        let wasSubmitting = isSubmittingWindowCloseWork
        isSubmittingWindowCloseWork = true
        defer { isSubmittingWindowCloseWork = wasSubmitting }
        guard let participant = wait.participant, isCloseWorkCurrent(wait, participant: participant),
            componentHost.buildLifecycle === stateMountCoordinator
        else {
            wait.isValid = false
            wait.isWaiting = false
            wait.coordinatorObserverPending = false
            pendingCloseBuildWait = nil
            return
        }
        if pendingLiveResizeSize != nil {
            completeCloseBuildWait(wait, participant: participant, submission: .unavailable)
            return
        }
        if case .unavailable = runtime.layoutSettlementStatus {
            completeCloseBuildWait(wait, participant: participant, submission: .unavailable)
            return
        }
        // Component settlement can be delivered inside an observed flush.
        // Preserve this exact wait for the outer flush's real completion.
        guard !hasPendingCloseHostWork, componentHost.isBuildSettled else { return }
        retireCloseBuildWait(wait)
        let submission = postCloseWork(wait, participant: participant)
        completeCloseBuildWait(wait, participant: participant, submission: submission)
        withExtendedLifetime((participant, wait)) {}
    }

    private func retireCloseBuildWait(_ wait: CloseBuildWait) {
        wait.isWaiting = false
        wait.coordinatorObserverPending = false
        if pendingCloseBuildWait === wait { pendingCloseBuildWait = nil }
    }

    private func completeCloseBuildWait(
        _ wait: CloseBuildWait, participant: any WindowCloseParticipant, submission: Win32DeferredCloseSubmission
    ) {
        // Retire before publishing failure, including a failed post after the
        // original caller already returned waitingForBuilds. No retry is added.
        retireCloseBuildWait(wait)
        wait.submission = submission
        switch submission {
        case .queued, .coalesced: break
        case .busy, .unavailable, .postFailed:
            if wait.isRegistering {
                wait.isValid = false
            } else {
                publishCloseWorkFailure(wait, participant: participant, submission: submission)
            }
        }
    }

    private func publishCloseWorkFailure(
        _ wait: CloseBuildWait, participant: any WindowCloseParticipant, submission: Win32DeferredCloseSubmission
    ) {
        guard !wait.hasPublishedFailure, isCloseWorkCurrent(wait, participant: participant) else { return }
        let wasSubmitting = isSubmittingWindowCloseWork
        isSubmittingWindowCloseWork = true
        defer { isSubmittingWindowCloseWork = wasSubmitting }
        wait.hasPublishedFailure = true
        wait.isValid = false
        wait.isWaiting = false
        wait.coordinatorObserverPending = false
        if pendingCloseBuildWait === wait { pendingCloseBuildWait = nil }
        withExtendedLifetime((self, participant, wait)) { wait.onSubmissionFailure(wait.ticket, submission) }
    }

    private func evaluateNativeClosePreflight(_ attempt: Win32CloseAttempt) -> Bool {
        if let existing = closePreflight, existing.attempt === attempt {
            guard !existing.hasFinished, let vote = existing.vote else { return false }
            guard vote == .reserved, let stamp = existing.stamp else {
                return recordClosePreflightRejection(vote, for: existing)
            }
            let decision = validateClosePreflight(existing, stamp: stamp)
            return decision == .reserved || recordClosePreflightRejection(decision, for: existing)
        }

        let preflight = ClosePreflight(attempt: attempt, participantIdentity: closeParticipantIdentity)
        closePreflight = preflight
        guard !hasTornDownWindow, let registration = windowCloseRegistration, registration.isCurrent else {
            return recordClosePreflightRejection(.unavailable, for: preflight)
        }
        // The separate document-session adapter must be installed explicitly.
        // This generic foundation does not activate native DocumentGroup close
        // or bypass its startup capability gate when the bundles are combined.
        guard !configuration.isDocumentGroup || windowCloseParticipant != nil else {
            return recordClosePreflightRejection(.unavailable, for: preflight)
        }
        guard !isEvaluatingWindowClosePolicy, !isPreparingWindowCloseCommit,
            !isReplacingWindowCloseParticipant, !isSubmittingWindowCloseWork, closeCommitReservation == nil
        else { return recordClosePreflightRejection(.busy(.closeInProgress), for: preflight) }
        if let rejection = closeBuildRejection(includingPendingReloads: false) {
            return recordClosePreflightRejection(rejection, for: preflight)
        }
        guard runtime.canPrepareLayoutSettlement else {
            return recordClosePreflightRejection(.unavailable, for: preflight)
        }

        isEvaluatingWindowClosePolicy = true
        defer { isEvaluatingWindowClosePolicy = false }
        let participant = windowCloseParticipant
        return withExtendedLifetime(participant) {
            // Consume at most one observed batch. Its completion may queue
            // another build or replace the participant, so check again below.
            flushObservedObjectReload(in: window, requestsFrame: false)
            guard !hasTornDownWindow, closeParticipantIdentity === preflight.participantIdentity,
                windowCloseRegistration === registration, !registration.isRevoked
            else { return recordClosePreflightRejection(.unavailable, for: preflight) }
            if let rejection = closeBuildRejection() {
                return recordClosePreflightRejection(rejection, for: preflight)
            }
            guard runtime.canPrepareLayoutSettlement else {
                return recordClosePreflightRejection(.unavailable, for: preflight)
            }

            // A layout-only query can run app builders, so it belongs here,
            // before any final lease. It never renders or presents a frame.
            _ = runtime.resolvedLayoutFrame(of: runtime.root)
            guard !hasTornDownWindow, !preflight.hasFinished, closePreflight === preflight,
                closeParticipantIdentity === preflight.participantIdentity,
                windowCloseRegistration === registration, !registration.isRevoked
            else { return recordClosePreflightRejection(.unavailable, for: preflight) }
            if let rejection = closeBuildRejection() {
                return recordClosePreflightRejection(rejection, for: preflight)
            }
            guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
                // Completed but unproven layout is terminal for this attempt;
                // neither this path nor the build observer retries it.
                return recordClosePreflightRejection(.unavailable, for: preflight)
            }
            let behavior = runtime.windowDismissalBehavior
            let stamp = ClosePreflightStamp(receipt: receipt, behavior: behavior, registration: registration)
            preflight.stamp = stamp
            syncWindowDismissBehavior(behavior)
            let afterPolicy = validateClosePreflight(preflight, stamp: stamp)
            guard afterPolicy == .reserved else {
                return recordClosePreflightRejection(afterPolicy, for: preflight)
            }

            if let participant, !participant.windowShouldClose(attempt) {
                let rejection: Win32CloseCommitDecision =
                    attempt.isUnavailable ? .unavailable : attempt.busyReason.map { .busy($0) } ?? .vetoed
                return recordClosePreflightRejection(rejection, for: preflight)
            }
            let afterParticipant = validateClosePreflight(preflight, stamp: stamp)
            guard afterParticipant == .reserved, !attempt.isUnavailable else {
                return recordClosePreflightRejection(
                    attempt.isUnavailable ? .unavailable : afterParticipant, for: preflight)
            }
            preflight.vote = .reserved
            return true
        }
    }

    private func recordClosePreflightRejection(
        _ decision: Win32CloseCommitDecision, for preflight: ClosePreflight
    ) -> Bool {
        preflight.vote = decision
        switch decision {
        case .unavailable: preflight.attempt.rejectAsUnavailable()
        case .busy(let reason): preflight.attempt.deferUntilReady(reason)
        case .reserved, .vetoed: break
        }
        return false
    }

    /// Pending observation/control batches count even when no root build is
    /// currently executing. A native live-resize size has not reached retained
    /// layout yet and cannot be repaired during final close validation.
    private func closeBuildRejection(includingPendingReloads: Bool = true) -> Win32CloseCommitDecision? {
        // Exhaustion is sticky even when a build or host batch is pending.
        // An ordinary earlier unproven resolution with a preparable runtime
        // can still receive its one bounded query on a fresh user request.
        if !runtime.canPrepareLayoutSettlement, case .unavailable = runtime.layoutSettlementStatus {
            return .unavailable
        }
        guard componentHost.buildLifecycle === stateMountCoordinator else { return .unavailable }
        guard pendingLiveResizeSize == nil else { return .unavailable }
        guard !isPerformingInitialContentBuild, observedReloadFlushDepth == 0, componentHost.isBuildSettled else {
            return .busy(.buildsNotSettled)
        }
        if includingPendingReloads,
            reloadScheduled || !pendingChangedObjects.isEmpty || !pendingObservedObjectContexts.isEmpty
                || pendingControlInvalidationContext != nil
        {
            return .busy(.buildsNotSettled)
        }
        return nil
    }

    /// Read the captured proof, never refresh it. The retained policy getter
    /// walks the tree, so only preflight calls it; policy setters invalidate
    /// the layout receipt. Every check here reads owned framework state.
    private func validateClosePreflight(
        _ preflight: ClosePreflight, stamp: ClosePreflightStamp, reservation: CloseReservation? = nil
    ) -> Win32CloseCommitDecision {
        guard !hasTornDownWindow, !preflight.hasFinished, closePreflight === preflight,
            window.activeCloseAttempt === preflight.attempt,
            closeParticipantIdentity === preflight.participantIdentity,
            windowCloseRegistration === stamp.registration, !stamp.registration.isRevoked
        else { return .unavailable }
        guard closeCommitReservation == nil || closeCommitReservation === reservation else {
            return .busy(.closeInProgress)
        }
        if let rejection = closeBuildRejection() { return rejection }
        guard runtime.isLayoutSettlementReceiptCurrent(stamp.receipt) else { return .unavailable }
        guard stamp.behavior != .disabled, window.isCloseButtonEnabled else { return .vetoed }
        return .reserved
    }

    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation {
        guard !isPreparingWindowCloseCommit else { return .busy(.closeInProgress) }
        guard let preflight = closePreflight, preflight.attempt === attempt,
            preflight.vote == .reserved, let stamp = preflight.stamp
        else { return .unavailable }
        let decision = validateClosePreflight(preflight, stamp: stamp)
        switch decision {
        case .vetoed: return .vetoed
        case .busy(let reason): return .busy(reason)
        case .unavailable: return .unavailable
        case .reserved: break
        }
        isPreparingWindowCloseCommit = true
        defer { isPreparingWindowCloseCommit = false }
        let participant = windowCloseParticipant
        var participantLease: (any Win32CloseCommitLease)?
        if let participant {
            switch participant.prepareCloseCommit(for: attempt) {
            case .ready(let lease): participantLease = lease
            case .vetoed: return .vetoed
            case .busy(let reason): return .busy(reason)
            case .unavailable: return .unavailable
            }
        }
        // Always hand a prepared participant lease to the native owner, even
        // if its preparation changed host state. Final validation rejects the
        // old stamp and native finish then rolls that exact lease back once.
        return .ready(
            CloseCommitLease(
                host: self, preflight: preflight, stamp: stamp,
                participant: participant, participantLease: participantLease))
    }

    private var isDocumentCloseSettled: Bool {
        canStartDocumentOperation && window.isCloseButtonEnabled
            && runtime.windowDismissalBehavior != .disabled
            && documentContext?.isRoutingDocument == false
            && documentContext?.session.hasActiveOperation == false
    }

    /// Deterministic test delivery only. An approval is consumed immediately
    /// before the simulated WM_DESTROY, with no application callback between
    /// the last checks and the session's write reservation.
    @discardableResult
    func commitHeadlessDocumentClose(_ approval: DocumentCloseApproval) -> Bool {
        guard let context = documentContext, context.host === self,
            window.nativeHandle == nil, !isEvaluatingWindowClosePolicy,
            context.owner.isValid, !hasTornDownWindow
        else { return false }
        flushObservedObjectReload(in: window, requestsFrame: false)
        syncWindowDismissBehavior()
        guard window.nativeHandle == nil, isDocumentCloseSettled,
            context.session.reserveClose(approval: approval, isHostSettled: true)
        else { return false }
        windowWillClose(window)
        return hasTornDownWindow
    }

    private func syncWindowDismissBehavior(_ capturedBehavior: RetainedWindowInteractionBehavior? = nil) {
        // Native preflight already captured the policy with its receipt. Keep
        // all affordance/policy-change handling on this common path without
        // walking the tree a second time or refreshing that receipt.
        let behavior = capturedBehavior ?? runtime.windowDismissalBehavior
        if documentContext != nil {
            if let previous = lastDocumentDismissBehavior, previous != behavior {
                documentContext?.session.invalidateCloseForHostChange()
            }
            lastDocumentDismissBehavior = behavior
        }
        // Failed-start rollback can already have torn down this host before
        // requesting native cleanup. It must not leave an unowned disabled
        // HWND alive; the idempotent teardown below will not run twice.
        window.setCloseButtonEnabled(hasTornDownWindow || behavior != .disabled)
    }

    func windowWillClose(_ window: Win32Window) {
        guard !hasTornDownWindow else { return }
        hasTornDownWindow = true
        documentContext?.owner.revoke()
        let closeWorkPin = windowCloseRegistration?.pinDeferredWork()
        let closingParticipant = windowCloseParticipant
        let closeBuildWait = pendingCloseBuildWait
        defer { withExtendedLifetime((closeWorkPin, closingParticipant, closeBuildWait)) {} }
        closeParticipantIdentity = CloseParticipantIdentity()
        windowCloseParticipant = nil
        closeBuildWait?.isValid = false
        closeBuildWait?.isWaiting = false
        closeBuildWait?.coordinatorObserverPending = false
        pendingCloseBuildWait = nil
        closePreflight?.hasFinished = true
        closeCommitReservation = nil
        windowCloseRegistration?.revoke()
        closingParticipant?.revokeCloseParticipation()
        componentHost.invalidateFileDialogRequests()
        runtime.stopRenderLifecycleCallbacks()
        // Revoke every capability before any ownership cleanup releases
        // application payloads that may reenter undo or escaped State bindings.
        let textInputTeardown = prepareTextInputUndoForWindowClose(in: runtime)
        stateMountCoordinator.close()
        documentContext?.invalidate()
        textInputTeardown.purgeHistory()
        runtime.cancelRenderLifecycleTasks()
        reloadScheduled = false
        pendingChangedObjects.removeAll()
        pendingObservedObjectContexts.removeAll()
        pendingControlInvalidationContext = nil
        pendingLiveResizeSize = nil
        pendingPresentation = false
        nextPresenterAttachAttemptAt = nil
        nextBatchRecoveryAttemptAt = nil
        resetObservedObjects()
        syncAnimationDriver(for: window)
        // Direct teardown and failed-start rollback need not receive native
        // capture/focus-loss messages. Cancel every input source after setting
        // the closed guard, so cleanup cannot reenter this host to start work.
        isPrimaryTouchActive = false
        runtime.pointerCancelled()
        runtime.keyboardFocusDidLeaveWindow()
        textInputTeardown.detach()
        uiaBridge?.disconnect()
        window.accessibilityProvider = nil
        // Release the GPU stack while the HWND is still alive. A swap chain
        // pins the window it presents to and nothing else in the process
        // will ever release it, so a closed window without this leaks its
        // whole device — including the blur ping-pong textures, which are
        // tens of megabytes at 4K.
        isRendererReady = false
        batchRenderer?.detach()
        renderer.detach()
        onWindowClosed?(self)
    }

    private var buildContext: ViewBuildContext {
        ViewBuildContext(
            stateMountCoordinator: stateMountCoordinator,
            canvasSizeProvider: { [weak self] in
                self?.runtime.root.frame.size
                    ?? Size(
                        width: Double(self?.configuration.size.width ?? 0),
                        height: Double(self?.configuration.size.height ?? 0)
                    )
            },
            invalidateHandler: { [weak self] in
                self?.reloadContentFromView()
            },
            stateMutationInvalidationHandler: { [weak self] in
                self?.reloadContentFromView(isStateMutation: true)
            },
            observedObjectHandler: { [weak self] object in
                self?.observeObject(object)
            },
            environmentValuesProvider: { [weak self] in
                let displayScale = self?.runtime.displayScale ?? 1
                return EnvironmentValues(
                    scenePhase: self?.resolvedScenePhase ?? .active,
                    controlActiveState: self?.resolvedControlActiveState ?? .active,
                    appearsActive: self?.resolvedAppearsActive ?? true,
                    supportsMultipleWindows: self?.windowEnvironment?.supportsMultipleWindows ?? false,
                    displayScale: displayScale,
                    pixelLength: Self.pixelLength(for: displayScale),
                    horizontalSizeClass: self?.resolvedHorizontalSizeClass ?? .regular,
                    verticalSizeClass: self?.resolvedVerticalSizeClass ?? .regular,
                    undoManager: self?.undoManager,
                    openWindow: self?.windowEnvironment?.openWindow ?? .noop,
                    dismissWindow: self?.windowEnvironment?.dismissWindow ?? .noop,
                    openSettings: self?.windowEnvironment?.openSettings ?? .noop,
                    newDocument: self?.windowEnvironment?.newDocument ?? .noop,
                    openDocument: self?.windowEnvironment?.openDocument ?? .noop,
                    saveDocument: self?.windowEnvironment?.saveDocument ?? .noop,
                    sceneStorageScope: self?.windowEnvironment?.sceneStorageScope ?? "shared"
                )
                .applyingSystemAppearance(self?.window.systemAppearance ?? .unavailable)
            }
        )
    }

    private static func pixelLength(for displayScale: Double) -> Double {
        displayScale > 0 ? 1 / displayScale : 1
    }

    private var resolvedScenePhase: ScenePhase {
        guard isWindowVisible else {
            return .background
        }

        return isWindowActive ? .active : .inactive
    }

    private var resolvedControlActiveState: ControlActiveState {
        guard isWindowVisible else {
            return .inactive
        }

        return isWindowActive ? .key : .inactive
    }

    private var resolvedAppearsActive: Bool {
        isWindowVisible && isWindowActive
    }

    private var resolvedHorizontalSizeClass: UserInterfaceSizeClass {
        Self.sizeClass(for: runtime.root.frame.size.width)
    }

    private var resolvedVerticalSizeClass: UserInterfaceSizeClass {
        Self.sizeClass(for: runtime.root.frame.size.height)
    }

    private static func sizeClass(for logicalLength: Double) -> UserInterfaceSizeClass {
        logicalLength < 600 ? .compact : .regular
    }

    private func buildRootComponent() -> Component {
        if let documentContext {
            let views = documentContext.makeContent()
            let errorMessage = documentContext.lastError?.localizedDescription
            guard !hasTornDownWindow, documentContext.owner.isValid else { return .empty }
            let body = composeComponent(from: views, context: buildContext)
            let status = makeViewComponent(
                Text(errorMessage ?? "")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("document.operation.error"),
                context: buildContext
            )
            return Component(key: "document-window:\(documentContext.session.sessionID)") { runtime in
                let bodyNode = body.makeNode(runtime: runtime)
                bodyNode.layoutFillAxes = .both
                let statusNode = status.makeNode(runtime: runtime)
                statusNode.isHidden = errorMessage == nil
                return Controls.panel(
                    layoutMode: .stack(.vertical()), isHitTestVisible: false,
                    children: [bodyNode, statusNode]
                )
            }
        }
        return composeComponent(from: configuration.content, context: buildContext)
    }

    private func reloadContentFromView(isStateMutation: Bool = false) {
        guard !hasTornDownWindow else { return }
        viewInvalidationGeneration &+= 1
        let generation = viewInvalidationGeneration
        if isStateMutation {
            pendingControlInvalidationContext = nil
        } else if componentHost.isBuilding, reloadScheduled {
            pendingControlInvalidationContext = ControlInvalidationContext(
                generation: generation,
                animation: currentAnimationTransaction,
                transaction: currentTransaction)
            return
        }
        // Controls request an immediate rebuild after writing their binding.
        // An observed-object binding may have queued its transaction during
        // that write, but its scope has ended by the time this invalidation
        // arrives. Consume that batch before an unscoped reload can snap the
        // model to its destination. State invalidation marks a newer mutation
        // whose current scope wins, including a plain unanimated write. A
        // control invalidation instead keeps the binding's captured scope,
        // even if it has already restored an outer withAnimation context.
        if !flushObservedObjectReload(
            in: window, requestsFrame: true, preservingCurrentTransaction: isStateMutation)
        {
            // A plain binding still needs this rebuild when no relevant
            // observed object changed, including a filtered unrelated batch.
            // A dependency hook can itself issue a newer invalidation.
            guard generation == viewInvalidationGeneration else { return }
            reloadContent()
        }
    }

    private func reloadContent(requestsFrame: Bool = true) {
        guard !hasTornDownWindow else { return }

        componentHost.reload(onCompleted: { [weak self] in
            self?.completeContentReload(requestsFrame: requestsFrame)
        })
    }

    private func completeContentReload(requestsFrame: Bool) {
        guard !hasTornDownWindow else { return }
        syncWindowDismissBehavior()
        uiaBridge?.raiseStructureChanged()

        // Present any file-importer / exporter / mover dialogs whose
        // isPresented binding has been set to true.
        componentHost.processPendingFileDialogs()
        guard !hasTornDownWindow else { return }

        onReloadContentCompleted?()
        if requestsFrame {
            commitRuntimeState(in: window)
        }
    }

    /// Manually observe an object for testing purposes.
    /// This allows tests to register observed objects without needing a view hierarchy.
    func observe(_ object: any ObservableObject) {
        guard !hasTornDownWindow else { return }
        manuallyObservedObjectIDs.insert(ObjectIdentifier(object))
        observeObject(object)
    }

    private func observeObject(_ object: any ObservableObject) {
        guard !hasTornDownWindow else { return }
        let identifier = ObjectIdentifier(object)
        guard observedObjectTokens[identifier] == nil else {
            return
        }

        observedObjectSubscriptionGeneration &+= 1
        let generation = observedObjectSubscriptionGeneration
        let token = ObservableObjectCenter.shared.addObserver(for: object) { [weak self] in
            guard let self, self.observedObjectTokens[identifier]?.generation == generation else { return }
            self.scheduleObservedObjectReload(for: identifier)
        }
        observedObjectTokens[identifier] = ObservedObjectSubscription(generation: generation, token: token)
        // The hook may close the window or observe this object again. Publish
        // the token first so either action sees the live registration.
        observedObjectRegistrationCount += 1
        onObservedObjectRegistered?(identifier)
    }

    /// Reconcile subscriptions only after an epoch resolves. Until then the
    /// committed tree and the candidate both keep their dependencies alive.
    /// Subtree epochs publish the coordinator's union, preserving sibling reads.
    private func updateObservedObjects(
        committed: Set<ObjectIdentifier>, retained: Set<ObjectIdentifier>, replacesRoot: Bool
    ) {
        guard !hasTornDownWindow else { return }
        if replacesRoot {
            manuallyObservedObjectIDs.removeAll()
        }
        let retainedSubscriptions = retained.union(manuallyObservedObjectIDs)
        let removedIdentifiers = Set(observedObjectTokens.keys).subtracting(retainedSubscriptions)
        let removedTokens = removedIdentifiers.compactMap { observedObjectTokens.removeValue(forKey: $0)?.token }
        componentHost.observedObjects = committed

        // A discarded dependency may already have sent a notification. Its
        // queued transaction must not trigger a later rebuild, including when
        // the committed dependency set is empty and manual observation is used.
        pendingChangedObjects.formIntersection(retainedSubscriptions)
        pendingObservedObjectContexts = pendingObservedObjectContexts.filter { retainedSubscriptions.contains($0.key) }
        for token in removedTokens {
            token.cancel()
        }
    }

    private func resetObservedObjects() {
        let tokens = observedObjectTokens.values.map(\.token)
        observedObjectTokens.removeAll()
        manuallyObservedObjectIDs.removeAll()
        componentHost.observedObjects.removeAll()
        for token in tokens {
            token.cancel()
        }
    }

    /// Reset all observability counters. Used by tests to establish baseline.
    func resetObservabilityCounters() {
        scheduledReloadCount = 0
        executedReloadCount = 0
        completedObservedObjectReloadTaskCount = 0
        skippedObservedObjectReloadCount = 0
        observedObjectRegistrationCount = 0
        reloadTriggeringObjectIDs.removeAll()
    }

    /// Current logical root size exposed for host-focused tests.
    var currentLogicalRootSize: IntSize {
        IntSize(
            width: Int32(runtime.root.frame.size.width),
            height: Int32(runtime.root.frame.size.height)
        )
    }

    /// Current display scale exposed for host-focused tests.
    var currentDisplayScale: Double {
        runtime.displayScale
    }

    /// Current runtime pacing interval exposed for host-focused tests.
    var currentRuntimeMinimumFrameInterval: Double? {
        runtime.minimumFrameInterval
    }

    /// Current presenter selection exposed for host-focused tests.
    var isUsingBatchPresentationBackend: Bool {
        activeBackend == .scene
    }

    /// Current scene/frame presenter selection exposed for host-focused tests.
    var isUsingScenePresentationBackend: Bool {
        activeBackend == .scene
    }

    /// Read-only health snapshot of the rendering pipeline. Cheap to fetch;
    /// safe to log periodically or display in a diagnostics overlay. The
    /// snapshot is computed on demand from the host's current state so it
    /// always reflects the latest backend selection and recovery schedule.
    public var rendererHealthSnapshot: RendererHealthSnapshot {
        let nextRecoveryInSeconds: Double? = {
            guard let dueAt = nextBatchRecoveryAttemptAt else { return nil }
            return max(0, dueAt - recoveryClock())
        }()
        let activeBackendName: String?
        switch activeBackend {
        case .scene:
            activeBackendName = batchRenderer?.backendDisplayName
        case .frame:
            activeBackendName = renderer.backendDisplayName
        }
        return RendererHealthSnapshot(
            activeBackend: activeBackend == .scene ? .scene : .frame,
            displayScale: runtime.displayScale,
            minimumFrameInterval: runtime.minimumFrameInterval,
            hasActiveAnimations: runtime.hasActiveAnimations,
            recoveryPolicyEnabled: recoveryPolicy.isEnabled,
            nextBatchRecoveryInSeconds: nextRecoveryInSeconds,
            lastBackendSelectionReason: currentPresentationSelection?.reason,
            activeBackendDisplayName: activeBackendName,
            lastScenePaintMetrics: runtime.lastScenePaintMetrics,
            lastPresentationFailureKind: lastPresentationFailureKind,
            isPresentationOccluded: activePresentationState.isOccluded,
            presentPacing: activePresentPacing,
            isPresenterUnavailable: isPresenterUnavailable,
            nextPresenterAttachInSeconds: nextPresenterAttachInSeconds,
            backendResolution: backendResolution
        )
    }

    /// Seconds until the next bounded presenter attach retry, `nil` when a
    /// presenter is attached or the terminal state was reached.
    private var nextPresenterAttachInSeconds: Double? {
        guard let dueAt = nextPresenterAttachAttemptAt else { return nil }
        return max(0, dueAt - recoveryClock())
    }

    /// The active backend's post-render presentation state. Backends that
    /// cannot lose a device report the neutral value.
    private var activePresentationState: PresentationState {
        switch activeBackend {
        case .scene:
            return batchRenderer?.presentationState ?? PresentationState()
        case .frame:
            return renderer.presentationState
        }
    }

    /// What is pacing the presenter that is actually on screen. Read once per
    /// frame by the self-pacing gate, so it must stay a property read and not
    /// become a computation.
    var activePresentPacing: PresentPacingStatus {
        switch activeBackend {
        case .scene:
            return batchRenderer?.presentPacing ?? PresentPacingStatus()
        case .frame:
            return renderer.presentPacing
        }
    }

    /// Schedule a batched reload.  Multiple rapid @Published changes within
    /// the same run-loop turn are coalesced into a single rebuild.
    ///
    /// Additionally, when the deferred reload fires, we check whether the
    /// ComponentHost actually depends on any of the objects that changed.  If
    /// none of the changed objects are in the host's dependency set, the
    /// rebuild is skipped entirely.
    private func scheduleObservedObjectReload(for changedObjectID: ObjectIdentifier) {
        guard !hasTornDownWindow, observedObjectTokens[changedObjectID] != nil else { return }
        pendingChangedObjects.insert(changedObjectID)
        observedObjectChangeSequence &+= 1
        pendingObservedObjectContexts[changedObjectID] = ObservedObjectReloadContext(
            sequence: observedObjectChangeSequence,
            animation: currentAnimationTransaction,
            transaction: currentTransaction)
        reloadTriggeringObjectIDs.insert(changedObjectID)

        guard !reloadScheduled else {
            // Same-turn coalescing: reload already scheduled, just accumulate the change
            onObservedObjectReloadScheduled?(changedObjectID, true)
            return
        }

        // New reload task being scheduled (not coalesced)
        reloadScheduled = true
        scheduledReloadCount += 1
        onObservedObjectReloadScheduled?(changedObjectID, false)
        guard !hasTornDownWindow else { return }

        // The native GetMessage/DispatchMessage loop does not yield to Swift's
        // main-actor executor. Give the batch a native wake as well as the
        // Task fallback used by hosts running under a cooperative executor.
        syncAnimationDriver(for: window)
        guard !hasTornDownWindow else { return }
        window.invalidate()

        // A live HWND has the wake above. Do not accumulate unserviceable
        // Swift Tasks behind its blocking native message loop.
        guard !hasTornDownWindow, window.nativeHandle == nil else { return }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.flushObservedObjectReload(in: self.window, requestsFrame: true)
        }
    }

    /// Either a native frame or the Task consumes a pending batch, never both.
    @discardableResult
    private func flushObservedObjectReload(
        in window: Win32Window, requestsFrame: Bool, preservingCurrentTransaction: Bool = false
    ) -> Bool {
        guard !hasTornDownWindow, reloadScheduled else { return false }
        // During construction the committed dependencies still describe the
        // previous tree. A newer State mutation is the exception: its caller
        // always queues a full root rebuild, covering the consumed older batch
        // under that mutation's transaction even if dependency filtering fails.
        guard !componentHost.isBuilding || preservingCurrentTransaction else { return false }
        observedReloadFlushDepth += 1
        defer {
            // The later transaction-restoration defers and every existing
            // completion have returned before this outermost notification.
            observedReloadFlushDepth -= 1
            if observedReloadFlushDepth == 0 { observedReloadFlushDidComplete() }
        }
        reloadScheduled = false

        let changedObjects = pendingChangedObjects
        let contexts = pendingObservedObjectContexts
        let controlInvalidation = pendingControlInvalidationContext
        pendingChangedObjects.removeAll()
        pendingObservedObjectContexts.removeAll()
        pendingControlInvalidationContext = nil

        let observedObjects = componentHost.observedObjects
        let relevantObjects =
            observedObjects.isEmpty ? changedObjects : changedObjects.intersection(observedObjects)

        guard let context = relevantObjects.compactMap({ contexts[$0] }).max(by: { $0.sequence < $1.sequence }) else {
            skippedObservedObjectReloadCount += 1
            completedObservedObjectReloadTaskCount += 1
            onObservedObjectReloadTaskCompleted?(false)
            syncAnimationDriver(for: window)
            if let controlInvalidation,
                !hasTornDownWindow,
                controlInvalidation.generation == viewInvalidationGeneration
            {
                let previousAnimation = currentAnimationTransaction
                let previousTransaction = currentTransaction
                currentAnimationTransaction = controlInvalidation.animation
                currentTransaction = controlInvalidation.transaction
                defer {
                    currentAnimationTransaction = previousAnimation
                    currentTransaction = previousTransaction
                }
                reloadContent(requestsFrame: requestsFrame)
                return true
            }
            return false
        }

        // The latest relevant mutation controls this coalesced rebuild.
        // An unrelated object's later notification must not erase its context.
        let previousAnimation = currentAnimationTransaction
        let previousTransaction = currentTransaction
        if !preservingCurrentTransaction {
            currentAnimationTransaction = context.animation
            currentTransaction = context.transaction
        }
        defer {
            currentAnimationTransaction = previousAnimation
            currentTransaction = previousTransaction
        }
        reloadContent(requestsFrame: requestsFrame)
        completedObservedObjectReloadTaskCount += 1
        onObservedObjectReloadTaskCompleted?(true)
        return true
    }

    private func commitRuntimeState(in window: Win32Window, interactive: Bool = false) {
        guard !hasTornDownWindow else { return }
        let needsPresentation = runtime.isDirty || pendingPresentation

        if interactive && needsPresentation {
            inputRateTracker.recordInput()
        }

        guard needsPresentation || inputRateTracker.isHighRate else {
            syncAnimationDriver(for: window)
            return
        }

        requestFrame(in: window)
    }

    private func requestFrame(in window: Win32Window) {
        guard !hasTornDownWindow else { return }
        let wasPending = pendingPresentation
        pendingPresentation = true
        syncAnimationDriver(for: window)
        if !wasPending {
            window.invalidate()
        }
    }

    @discardableResult
    private func renderCurrentFrame(in window: Win32Window, timestamp: Double? = nil) -> Bool {
        guard !hasTornDownWindow else { return false }
        // The drag's newest size, applied once, here — not once per mouse
        // report in the wndproc. Before the presenter check, so the runtime's
        // root is the window's size even on a frame that cannot be presented.
        applyPendingLiveResizeIfNeeded(in: window)

        if !isRendererReady {
            // Never invalidate from here: this runs inside `WM_PAINT`'s
            // BeginPaint/EndPaint pair, where `InvalidateRect` re-dirties the
            // region `BeginPaint` just validated and the window spins forever.
            // The attach retry is clock-gated and bounded, so an unpaintable
            // window costs a comparison per paint request, not a core.
            guard attemptPresenterAttachRetryIfDue(in: window) else {
                return false
            }
        }

        // A scene-content failure reproduces on the scene that produced it, so
        // the recovery gate below needs to know whether the tree has changed
        // since. Sampled here, before the render consumes the dirty flags.
        if runtime.isDirty {
            didSceneContentChangeSinceFailure = true
        }

        // Opportunistic recovery: if we previously downgraded and the
        // configured policy permits, try re-attaching the batch backend
        // before this frame's render path picks a backend.
        // A content failure must see this frame's animation changes before
        // deciding that the scene is unchanged and extending its backoff.
        let recoveryNeedsAnimationSample =
            lastPresentationFailureKind == .sceneContent && (runtime.hasActiveAnimations || reloadScheduled)
        if !recoveryNeedsAnimationSample {
            attemptBatchBackendRecoveryIfDue(in: window)
        }

        guard
            reloadScheduled || runtime.isDirty || pendingPresentation || runtime.hasActiveAnimations
                || inputRateTracker.isHighRate
        else {
            syncAnimationDriver(for: window)
            return false
        }

        // One monotonic clock for every entry point, `WM_PAINT` included.
        let frameTimestamp = timestamp ?? frameClock()

        // Self-paced presentation: `Present` is no longer waiting for anything,
        // so this gate is the only thing between the window and a frame loop
        // that runs as fast as the CPU allows. Deferring here is a wait on the
        // frame clock, not a spin — `WM_PAINT` validated the region before this
        // call, nothing re-invalidates it, and the deferred frame is re-armed
        // on the animation timer by `syncAnimationDriver`.
        guard isFrameDueUnderSelfPacing(at: frameTimestamp) else {
            syncAnimationDriver(for: window)
            return false
        }

        // Only paid for when a diagnostics run is listening: `frameClock()` is
        // a QPC round-trip, and this is the frame loop.
        let isSamplingFrames = onFramePresented != nil
        let outsideFrameRebuildSeconds = pendingRebuildSeconds
        let frameStartedAt = isSamplingFrames ? frameClock() : 0
        // Coalesce @Published changes until a frame is admitted, without
        // invalidating again from inside BeginPaint/EndPaint. A rejected
        // dependency must not turn its native wake into a duplicate present.
        flushObservedObjectReload(in: window, requestsFrame: false)
        guard !hasTornDownWindow else { return false }
        guard runtime.isDirty || pendingPresentation || runtime.hasActiveAnimations || inputRateTracker.isHighRate
        else {
            syncAnimationDriver(for: window)
            return false
        }
        // Every admitted frame advances the same animation clock, including
        // WM_PAINT-driven frames. Ticking only from WM_TIMER let an input paint
        // consume a presentation slot with the preceding tick's values.
        _ = runtime.tickAnimations(at: frameTimestamp)
        if runtime.isDirty {
            didSceneContentChangeSinceFailure = true
        }
        if recoveryNeedsAnimationSample {
            attemptBatchBackendRecoveryIfDue(in: window)
        }
        let rebuildsBefore = runtime.sceneRebuildCount
        var sceneBuildEndedAt = frameStartedAt
        var bindEndedAt = frameStartedAt
        var primitiveCount = 0
        var visitedNodeCount = 0
        var frameSubmission: BackendFrameSubmission?

        do {
            if activeBackend == .scene, let batchRenderer {
                let scene = sceneRenderer(runtime, frameTimestamp)
                guard !hasTornDownWindow else { return false }
                if isSamplingFrames {
                    sceneBuildEndedAt = frameClock()
                    primitiveCount = scene.layers.reduce(0) { $0 + $1.paintOperations.count }
                    visitedNodeCount = scene.paintMetrics.nodesVisited
                }
                if shouldSkipIdenticalPresent() {
                    recordSkippedIdenticalPresent(in: window)
                    return false
                }
                batchRenderer.bindResources(for: scene)
                if isSamplingFrames {
                    bindEndedAt = frameClock()
                }
                do {
                    // Capture the attempt before recovery/fallback can replace
                    // the device or detach the batch backend. A bind failure
                    // never reads the preceding attempt's submission record.
                    // This reads cached metadata only; the existing potentially
                    // expensive diagnostics lookup stays after the frame timer.
                    defer {
                        if isSamplingFrames { frameSubmission = batchRenderer.lastFrameSubmission }
                    }
                    try batchRenderer.render(scene: scene)
                }
                noteSuccessfulSceneFrame()
            } else {
                let frame = runtime.renderFrame(at: frameTimestamp)
                guard !hasTornDownWindow else { return false }
                if isSamplingFrames {
                    sceneBuildEndedAt = frameClock()
                    bindEndedAt = sceneBuildEndedAt
                }
                if shouldSkipIdenticalPresent() {
                    recordSkippedIdenticalPresent(in: window)
                    return false
                }
                try renderer.render(frame: frame)
            }
        } catch {
            guard !hasTornDownWindow else { return false }
            guard activeBackend == .scene else {
                // Frame-path render failure: policy is to keep the session
                // alive and log — rate-limited, because a deterministic
                // failure repeats at frame rate and `report` is synchronous
                // console I/O on the UI thread.
                reportRepeating(String(describing: error), signature: "frame-render-failure")
                return false
            }

            var didAttachFrameBackend = false
            do {
                try fallbackToFrameRenderer(
                    becauseOf: .batchRenderFailure(String(describing: error)),
                    failureKind: PresentationFailureKind.classifying(error),
                    in: window
                )
                didAttachFrameBackend = true
                let frame = runtime.renderFrame(at: frameTimestamp)
                guard !hasTornDownWindow else { return false }
                try renderer.render(frame: frame)
            } catch {
                guard didAttachFrameBackend else {
                    // Both presenters are gone. Leaving `activeBackend` on
                    // `.scene` here is what made every following tick rebuild
                    // the scene, fail, fail the fallback and print twice — at
                    // frame rate, for the rest of the session. Pin to frame,
                    // drop out of the ready state and let the bounded attach
                    // retry own recovery from here.
                    activeBackend = .frame
                    recordPresenterAttachFailure(String(describing: error), in: window)
                    return false
                }

                reportRepeating(String(describing: error), signature: "frame-render-failure")
                return false
            }
        }

        // A backend that just rebuilt its device deliberately skipped a
        // frame, so the pixels on screen are stale even though nothing is
        // dirty. Ask for one more frame rather than waiting for the next
        // user interaction. Set through `pendingPresentation` — not
        // `window.invalidate()` — because this runs inside `WM_PAINT`'s
        // BeginPaint/EndPaint pair, where re-dirtying the region would spin.
        // Sampled before the presentation bookkeeping below, so the submit
        // figure is the backend's cost and not the frame loop's.
        let renderEndedAt = isSamplingFrames ? frameClock() : 0

        // What is on screen is now exactly this revision; the next frame that
        // would present the same one has nothing to add.
        lastPresentedContentRevision = runtime.contentRevision
        persistPacingVerdictIfChanged()

        let owesRepaint = activePresentationState.needsImmediateRepaint
        pendingPresentation =
            runtime.isDirty || runtime.hasActiveAnimations || inputRateTracker.isHighRate || owesRepaint
        syncAnimationDriver(for: window)

        if let onFramePresented {
            let frameEndedAt = frameClock()
            let backendDiagnostics = activeBatchBackendDiagnostics
            let rebuildSeconds = pendingRebuildSeconds
            let rebuildCount = pendingRebuildCount
            let composeSeconds = pendingComposeSeconds
            let nodeConstructionSeconds = pendingNodeConstructionSeconds
            let reconcileSeconds = pendingReconcileSeconds
            let rebuildPhaseTimingsAvailable = pendingRebuildPhaseTimingsAvailable && rebuildCount > 0
            pendingRebuildSeconds = 0
            pendingRebuildCount = 0
            pendingRebuildPhaseTimingsAvailable = true
            pendingComposeSeconds = 0
            pendingNodeConstructionSeconds = 0
            pendingReconcileSeconds = 0
            let didRebuildScene = runtime.sceneRebuildCount != rebuildsBefore
            onFramePresented(
                LiveFrameSample(
                    presentedAt: frameEndedAt,
                    totalSeconds: frameEndedAt - frameStartedAt,
                    rebuildSeconds: rebuildSeconds,
                    outsideFrameRebuildSeconds: outsideFrameRebuildSeconds,
                    rebuildCount: rebuildCount,
                    rebuildPhaseTimingsAvailable: rebuildPhaseTimingsAvailable,
                    composeSeconds: composeSeconds,
                    nodeConstructionSeconds: nodeConstructionSeconds,
                    reconcileSeconds: reconcileSeconds,
                    sceneBuildSeconds: sceneBuildEndedAt - frameStartedAt,
                    layoutSeconds: didRebuildScene ? runtime.lastLayoutSeconds : 0,
                    paintSeconds: didRebuildScene ? runtime.lastPaintSeconds : 0,
                    bindSeconds: bindEndedAt - sceneBuildEndedAt,
                    backendSubmitSeconds: backendDiagnostics?.lastSubmitSeconds ?? 0,
                    backendPresentSeconds: backendDiagnostics?.lastPresentSeconds ?? 0,
                    backendTimingsAvailable: backendDiagnostics != nil,
                    submitAndPresentSeconds: renderEndedAt - bindEndedAt,
                    didRebuildScene: didRebuildScene,
                    nodeReplayCount: runtime.lastSceneNodeReplayCount,
                    primitiveCount: primitiveCount,
                    hadActiveAnimations: runtime.hasActiveAnimations,
                    backend: activeBackend == .scene ? .scene : .frame,
                    backendFrameSubmission: frameSubmission,
                    gpuTimingAdapterIsSoftware: frameSubmission?.adapterIsSoftware,
                    atlasUploadedByteCount: backendDiagnostics?.atlasUploadedByteCount ?? 0,
                    drawCallCount: backendDiagnostics?.lastDrawCallCount ?? 0,
                    drawnInstanceCount: backendDiagnostics?.lastDrawnInstanceCount ?? 0,
                    visitedNodeCount: visitedNodeCount
                )
            )
        }

        return true
    }

    /// Tells both presenters what one display period costs, and keeps the
    /// self-pacer's target in step with it.
    ///
    /// - Parameter force: pushes the value even when it has not changed, for
    ///   the case a backend was just attached and has never been told.
    private func applyDisplayFrameInterval(_ seconds: Double, force: Bool = false) {
        guard seconds.isFinite, seconds > 0 else {
            return
        }
        guard force || seconds != displayFrameInterval else {
            return
        }
        displayFrameInterval = seconds
        // The gate schedules on the true period — see `selfPacedFrameInterval`.
        selfPacedFrameInterval = seconds
        // A display change invalidates the deadline the old one set.
        selfPacedFrameDueAt = 0
        batchRenderer?.setDisplayFrameInterval(seconds)
        renderer.setDisplayFrameInterval(seconds)
    }

    /// Whether the frame about to be presented is byte-identical to the one
    /// already on screen, and may therefore be dropped.
    ///
    /// Only while an animation is active, deliberately. An animating window's
    /// timer keeps ticking, so a skipped duplicate is followed by a tick that
    /// advances the animation and presents a frame that differs — smoothness
    /// is preserved and the duplicate simply vanishes. An idle window has no
    /// such next tick: its presents are driven by explicit requests (a
    /// diagnostics pump, the input-rate tracker), and refusing those would
    /// starve the very loop that asked. A device rebuild
    /// (`needsImmediateRepaint`) presents unconditionally — the swap chain's
    /// pixels are gone even though the revision says nothing changed.
    private func shouldSkipIdenticalPresent() -> Bool {
        guard runtime.hasActiveAnimations,
            !activePresentationState.needsImmediateRepaint,
            let lastPresented = lastPresentedContentRevision,
            lastPresented == runtime.contentRevision
        else {
            return false
        }
        return true
    }

    /// Books a skipped duplicate: the frame loop stays armed (the animation
    /// that made the skip safe still needs its next tick), the schedule slot
    /// the self-paced gate granted is simply left unused, and the skip is
    /// counted where diagnostics can see it.
    private func recordSkippedIdenticalPresent(in window: Win32Window) {
        skippedIdenticalPresentCount += 1
        pendingPresentation =
            runtime.isDirty || runtime.hasActiveAnimations || inputRateTracker.isHighRate
        syncAnimationDriver(for: window)
    }

    /// Forgets what is on screen, so the next frame presents unconditionally.
    /// Called wherever the pixels underneath the bookkeeping are replaced:
    /// presenter attach, backend switch, resize.
    private func invalidatePresentedContentTracking() {
        lastPresentedContentRevision = nil
    }

    // MARK: - Present-pacing memory

    /// The key this window's pacing verdict is filed under: the adapter that
    /// presents plus the display it presents to. Either changing is a new
    /// bargain, judged fresh.
    private func computePresentPacingMemoryKey() -> String {
        let adapter =
            activeBatchBackendDiagnostics?.adapterDescription
            ?? (activeBackend == .scene
                ? batchRenderer?.backendDisplayName ?? renderer.backendDisplayName
                : renderer.backendDisplayName)
        return "\(adapter)|\(window.displayIdentity())"
    }

    /// Consults the persisted verdict at presenter attach and seeds *both*
    /// presenters when it says self-paced — the frame fallback carries the
    /// same watchdog, and a downgrade mid-session must not resurrect the
    /// launch slideshow. First launch on a broken machine still pays the
    /// evidence bar once; every later launch starts smooth and pays one
    /// immediate confirmation probe instead
    /// (`PresentPacingPolicy.adoptRememberedSelfPacing`).
    private func seedPresentPacingFromMemoryIfRemembered() {
        guard let presentPacingMemory else {
            return
        }

        let key = computePresentPacingMemoryKey()
        presentPacingMemoryKey = key
        lastPersistedPacingVerdict = nil
        guard presentPacingMemory.remembersSelfPacing(forKey: key) else {
            return
        }

        batchRenderer?.adoptRememberedSelfPacing()
        renderer.adoptRememberedSelfPacing()
    }

    /// Files the watchdog's current verdict after a presented frame. Only the
    /// two settled modes are verdicts: a probe in flight and a measurement
    /// override say nothing about the display. `selfPaced` writes the memory;
    /// `displayPaced` — the launch default, and where a passed probe lands —
    /// drops it, which is exactly "drop the memory when a probe passes".
    private func persistPacingVerdictIfChanged() {
        guard let presentPacingMemory, let presentPacingMemoryKey else {
            return
        }

        let verdict: Bool?
        switch activePresentPacing.mode {
        case .selfPaced:
            verdict = true
        case .displayPaced:
            verdict = false
        case .probingDisplay, .unsynchronized:
            verdict = nil
        }

        guard let verdict, verdict != lastPersistedPacingVerdict else {
            return
        }

        lastPersistedPacingVerdict = verdict
        presentPacingMemory.setRemembersSelfPacing(verdict, forKey: presentPacingMemoryKey)
    }

    /// Whether the self-paced frame gate lets this frame through.
    ///
    /// Returns `true` immediately whenever the display is doing the pacing —
    /// the gate exists only for the state where it is not, and adding a second
    /// pacer on top of a working `Present(1)` would fight it.
    ///
    /// The schedule is phase-locked rather than "last frame plus a period":
    /// deadlines advance by whole display periods, so a frame released a
    /// fraction early does not pull every later deadline forward with it, and
    /// the long-run rate is exactly the display's. A stall that puts the
    /// schedule more than one period in the past re-synchronises instead of
    /// trying to catch up with a burst nobody can see.
    private func isFrameDueUnderSelfPacing(at timestamp: Double) -> Bool {
        guard activePresentPacing.requiresSelfPacing else {
            selfPacedFrameDueAt = 0
            return true
        }

        guard selfPacedFrameDueAt > 0 else {
            selfPacedFrameDueAt = timestamp + selfPacedFrameInterval
            return true
        }

        guard timestamp + Self.selfPacedEarlyTolerance >= selfPacedFrameDueAt else {
            return false
        }

        var nextDueAt = selfPacedFrameDueAt + selfPacedFrameInterval
        if nextDueAt <= timestamp {
            nextDueAt = timestamp + selfPacedFrameInterval
        }
        selfPacedFrameDueAt = nextDueAt
        return true
    }

    /// Seconds the self-paced gate still owes the next frame, or `nil` when
    /// nothing is being held back. What turns the deferral into a timed sleep
    /// rather than a retry loop.
    private func secondsUntilSelfPacedFrame(at timestamp: Double) -> Double? {
        guard selfPacedFrameDueAt > 0, activePresentPacing.requiresSelfPacing else {
            return nil
        }
        let remaining = selfPacedFrameDueAt - Self.selfPacedEarlyTolerance - timestamp
        return remaining > 0 ? remaining : nil
    }

    private func syncAnimationDriver(for window: Win32Window) {
        guard !hasTornDownWindow else {
            window.setAnimationTimerEnabled(false)
            currentTimerState = TimerState(
                isEnabled: false,
                intervalMilliseconds: currentTimerState.intervalMilliseconds,
                usesHighResolution: currentTimerState.usesHighResolution,
                refreshRate: currentTimerState.refreshRate)
            return
        }
        let refreshRate = max(Int(window.monitorRefreshRate), 1)
        runtime.minimumFrameInterval = Self.pacingInterval(forRefreshRate: refreshRate)
        window.useHighResolutionTimer = true
        applyDisplayFrameInterval(1.0 / Double(refreshRate))

        // Without a presenter there is nothing to animate and nothing to
        // present, so the timer's only remaining job is the bounded attach
        // retry — at its own coarse cadence. In the terminal state it has no
        // job at all and stops.
        if !isRendererReady, isPresenterUnavailable || nextPresenterAttachAttemptAt != nil {
            let shouldRetry = !isPresenterUnavailable
            let retryInterval = Self.presenterAttachRetryIntervalMilliseconds
            window.setAnimationTimerEnabled(shouldRetry, intervalMilliseconds: retryInterval)
            let retryState = TimerState(
                isEnabled: shouldRetry,
                intervalMilliseconds: retryInterval,
                usesHighResolution: true,
                refreshRate: UInt32(refreshRate)
            )
            currentTimerState = retryState
            onTimerStateChanged?(retryState)
            return
        }

        var intervalMilliseconds = Self.animationTimerIntervalMilliseconds(forRefreshRate: refreshRate)
        // A frame the self-paced gate deferred is owed a wake-up at its
        // deadline, which is sooner than the display cadence. Shortening the
        // timer is how the deferral sleeps: no spin, no dropped frame.
        if let waitSeconds = secondsUntilSelfPacedFrame(at: frameClock()) {
            let waitMilliseconds = UInt32(max(1, Int((waitSeconds * 1000).rounded(.up))))
            intervalMilliseconds = min(intervalMilliseconds, waitMilliseconds)
        }
        let shouldDriveFrames =
            reloadScheduled || runtime.hasActiveAnimations || runtime.isDirty || pendingPresentation
            || inputRateTracker.isHighRate
        window.setAnimationTimerEnabled(shouldDriveFrames, intervalMilliseconds: intervalMilliseconds)

        // Record timer state for observability (testing and debugging)
        let newState = TimerState(
            isEnabled: shouldDriveFrames,
            intervalMilliseconds: intervalMilliseconds,
            usesHighResolution: true,
            refreshRate: UInt32(refreshRate)
        )
        currentTimerState = newState
        onTimerStateChanged?(newState)
    }

    private func logicalSize(for surface: SurfaceDescriptor) -> IntSize {
        logicalSize(for: surface.pixelSize, scaleFactor: surface.scaleFactor)
    }

    /// Pixels → points, through the one clamped scale
    /// (`Win32Window.effectiveScaleFactor`) that the root size, the runtime's
    /// display scale, hit testing, the IME caret rect and `clientRectToScreen`
    /// all share. Clamping here and not in `logicalPoint` is what put a 0.75
    /// session's clicks a third away from the elements they landed on.
    private func logicalSize(for pixelSize: IntSize, scaleFactor: Double) -> IntSize {
        let logicalScale = Win32Window.effectiveScaleFactor(for: scaleFactor)
        return IntSize(
            width: Int32((Double(pixelSize.width) / logicalScale).rounded(.toNearestOrAwayFromZero)),
            height: Int32((Double(pixelSize.height) / logicalScale).rounded(.toNearestOrAwayFromZero))
        )
    }

    private func logicalPoint(_ point: Point, scaleFactor: Double) -> Point {
        let logicalScale = Win32Window.effectiveScaleFactor(for: scaleFactor)
        return Point(x: point.x / logicalScale, y: point.y / logicalScale)
    }

    private static func defaultSurfaceDescriptor(for window: Win32Window) -> SurfaceDescriptor? {
        guard let handle = window.nativeHandle else {
            return nil
        }

        return SurfaceDescriptor(
            windowHandle: handle,
            pixelSize: window.currentClientSize(),
            scaleFactor: window.effectiveScaleFactor
        )
    }

    // MARK: - Frame fallback policy (Phase 6)
    //
    // Scene vs frame is an explicit product policy with observable health and
    // recovery, not an accidental downgrade. The table below is the source of
    // truth for the behaviour implemented in `attachPreferredRenderer`,
    // `renderCurrentFrame`, `resizeActiveRenderer`,
    // `fallbackToFrameRenderer`, and `attemptBatchBackendRecoveryIfDue`
    // (docs/StabilizationRoadmap.md Phase 6 mirrors it).
    //
    // | Trigger                                  | Policy                                                        |
    // |------------------------------------------|---------------------------------------------------------------|
    // | Startup, batch available                 | Attach batch (scene) backend; reason `.defaultScene`.          |
    // | Startup batch attach throws              | Downgrade to frame immediately; reason `.batchAttachFailure`,  |
    // |                                          | and schedule recovery like any other downgrade.                |
    // | Batch `render(scene:)` throws mid-frame  | Render that frame on the frame backend, then pin to frame;     |
    // |                                          | reason `.batchRenderFailure`.                                  |
    // | Batch `resize` throws                    | Downgrade at the new size; reason `.batchResizeFailure`.       |
    // | After any downgrade, `.standard` policy  | Retry batch attach with exponential backoff (5s → 60s cap);    |
    // |                                          | success restores scene with reason `.batchBackendRecovered`.   |
    // | Downgrade classified `.permanent`        | No recovery is scheduled: the machine cannot do it.            |
    // | After any downgrade, `.disabled` policy  | One-way pin: batch is never invoked again this session.        |
    // | Frame backend itself throws              | Log (rate-limited); the host session stays alive (no crash).   |
    // | Neither backend can attach               | Bounded attach retry (5 × 0.5s→8s) on a 250 ms timer, then a  |
    // |                                          | terminal `.presenterUnavailable` state that stops requesting   |
    // |                                          | frames; observable as                                          |
    // |                                          | `RendererHealthSnapshot.isPresenterUnavailable`. A 0×0 client  |
    // |                                          | rect (minimized) defers an attempt rather than spending one.   |
    // | Startup probe says the factory cannot    | The composition root substitutes a factory that can actually   |
    // | present here                             | blit (`SoftwareWindowRenderBackendFactory`), never one that    |
    // |                                          | only rasterizes into memory; a fallback that cannot present    |
    // |                                          | either is not substituted, so the row above applies. Recorded  |
    // |                                          | in `RendererHealthSnapshot.backendResolution`.                 |
    //
    // A window with no presenter never invalidates itself: the not-ready
    // branch of `renderCurrentFrame` runs inside `WM_PAINT`'s
    // BeginPaint/EndPaint pair, so `InvalidateRect` there re-dirties the region
    // `BeginPaint` just validated and the window spins at 100 % CPU showing
    // nothing. See docs/GPURenderingPipeline.md § 4d.
    //
    // Device loss is *not* in that table, and deliberately so: it is not a
    // backend being bad, it is a device being gone, and switching backends
    // would only create the next device on the same dead adapter. Both D3D11
    // renderers rebuild their own device in place (see `DeviceLostPolicy`)
    // and only surface a failure here once bounded recovery is exhausted —
    // at which point it arrives typed `.deviceLost` in
    // `RendererHealthSnapshot.lastPresentationFailureKind`. A backend that
    // rebuilt its device reports `needsImmediateRepaint`, and the frame loop
    // schedules the frame it skipped.
    //
    // Every transition in that table releases the outgoing backend before
    // the incoming one attaches (`detach()`, see docs/GPURenderingPipeline.md
    // § 4b). A flip-model swap chain owns its HWND exclusively, so "both
    // backends attached to one window" is not a state this policy may enter,
    // in either direction — and `windowWillClose` detaches both, because
    // nothing else in the process ever releases a swap chain.
    //
    // What apps may force:
    // - `SWIFT_WINDOWSUI_FRAME_DEBUG=1` (`StartupPresentationMode.frameDebug`,
    //   `-FrameDebug` tooling): pins the frame backend from startup, reason
    //   `.frameDebugOverride`; batch is never attached.
    // - `recoveryPolicy: .disabled` on the host: opts out of two-way recovery.
    // - `WinSwiftUIWindowHost.rendererHealthSnapshot`: public observability of
    //   active backend, selection reason, and recovery countdown.
    //
    // Readability contract on the frame path (enforced by
    // `FramePathDegradationTests` / `FrameFallbackPolicyTests`): text rides
    // pre-rasterized bitmaps, fillRect keeps solid/linear-gradient fills with
    // uniform corner radii, and vector path commands are CPU-rasterized into
    // drawBitmaps by `FramePathDegradation` inside `D3D11Renderer`. Known
    // cosmetic gaps vs the scene path (documented, not claimed as parity):
    // rounded clip shapes degrade to rectangular clips, per-corner radii fall
    // back to uniform, radial/conic gradients fall back to a solid base color,
    // and soft shadows render as plain offset fills.

    private func attachPreferredRenderer(to surface: SurfaceDescriptor) throws {
        if startupPresentationMode == .frameDebug {
            try renderer.attach(to: surface)
            activeBackend = .frame
            updatePresentationSelection(reason: .frameDebugOverride)
            return
        }

        if let batchRenderer {
            do {
                try batchRenderer.attach(to: surface)
                activeBackend = .scene
                updatePresentationSelection(reason: .defaultScene)
                return
            } catch {
                reportRepeating(
                    "Batch renderer attach failed; falling back to frame renderer. \(error)",
                    signature: "batch-attach-failure"
                )
                // A partially-attached batch backend may already own a swap
                // chain for this HWND, and flip-model presentation is
                // exclusive per window: release it before the frame backend
                // asks DXGI for a second one.
                batchRenderer.detach()
                try renderer.attach(to: surface)
                activeBackend = .frame
                lastPresentationFailureKind = PresentationFailureKind.classifying(error)
                updatePresentationSelection(reason: .batchAttachFailure(String(describing: error)))
                // A startup attach failure is a downgrade like any other, and
                // the policy table promises recovery after any downgrade. A
                // driver that was mid-upgrade when the window opened used to
                // pin the app to the frame backend for the whole session,
                // because this was the one downgrade path that scheduled
                // nothing and `nextBatchRecoveryAttemptAt` is set nowhere
                // else.
                scheduleBatchBackendRecoveryIfNeeded()
                return
            }
        }

        try renderer.attach(to: surface)
        activeBackend = .frame
        updatePresentationSelection(reason: .batchRendererUnavailable)
    }

    private func resizeActiveRenderer(to size: IntSize, in window: Win32Window) throws {
        // Resized swap-chain buffers do not carry the old pixels; whatever
        // revision was on screen is gone with them.
        invalidatePresentedContentTracking()
        if activeBackend == .scene, let batchRenderer {
            do {
                try batchRenderer.resize(to: size)
                return
            } catch {
                try fallbackToFrameRenderer(
                    becauseOf: .batchResizeFailure(String(describing: error)),
                    failureKind: PresentationFailureKind.classifying(error),
                    in: window
                )
            }
        }

        try renderer.resize(to: size)
    }

    private func fallbackToFrameRenderer(
        becauseOf reason: PresentationSelectionReason,
        failureKind: PresentationFailureKind? = nil,
        in window: Win32Window
    ) throws {
        lastPresentationFailureKind = failureKind
        // Rate-limited: a deterministic scene failure downgrades on every
        // frame it is retried on, and this used to be one synchronous console
        // write per attempt on the UI thread.
        if let detail = reason.detail {
            reportRepeating(
                "Batch renderer failed; switching to frame renderer. \(detail)",
                signature: "batch-downgrade-\(reason.probeCode)"
            )
        } else {
            reportRepeating(
                "Batch renderer failed; switching to frame renderer.",
                signature: "batch-downgrade-\(reason.probeCode)"
            )
        }

        let surface = surfaceDescriptor ?? surfaceDescriptorProvider(window)
        guard let surface else {
            throw NSError(
                domain: "WinSwiftUIWindowHost",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing surface descriptor during frame fallback."]
            )
        }

        surfaceDescriptor = surface
        // Presenter switch: the batch backend still owns a flip-model swap
        // chain on this HWND, and DXGI treats that ownership as exclusive.
        // Without this release the frame backend's `CreateSwapChainForHwnd`
        // throws and the window freezes on its last presented frame.
        batchRenderer?.detach()
        try renderer.attach(to: surface)
        try renderer.resize(to: surface.pixelSize)
        activeBackend = .frame
        isRendererReady = true
        invalidatePresentedContentTracking()
        updatePresentationSelection(reason: reason)
        scheduleBatchBackendRecoveryIfNeeded()
    }

    /// Counts a frame the scene backend actually presented, and retires the
    /// recovery ladder once it has presented enough of them in a row.
    private func noteSuccessfulSceneFrame() {
        guard didDowngradeSinceHealthySceneRun else {
            return
        }

        consecutiveSuccessfulSceneFrames += 1
        guard consecutiveSuccessfulSceneFrames >= Self.healthySceneFrameThreshold else {
            return
        }

        // The scene backend has carried the session for half a second. A
        // failure after this is new information, so the next downgrade starts
        // the ladder over rather than continuing yesterday's.
        didDowngradeSinceHealthySceneRun = false
        currentBatchRecoveryInterval = recoveryPolicy.initialRetryInterval
        lastPresentationFailureKind = nil
    }

    /// After a downgrade, if the recovery policy is enabled, set the next
    /// attempt timestamp.
    ///
    /// The backoff is *carried across downgrades*. Resetting it here — which
    /// is what this did — combined with `attemptBatchBackendRecoveryIfDue`
    /// only extending it on *attach* failure produced the recovery flap: a
    /// healthy device with one unrenderable scene re-attaches trivially, so a
    /// single unuploadable image oscillated the app between two visibly
    /// different backends every 5 seconds for the rest of the session, each
    /// cycle costing a full scene build and a failed present. The ladder now
    /// only restarts after the scene backend has presented
    /// ``healthySceneFrameThreshold`` consecutive frames.
    ///
    /// A `.permanent` failure — no adapter, a missing feature level, an
    /// unsupported format — schedules nothing: retrying it every 5s for the
    /// rest of the session costs a full scene build and a visible backend
    /// switch per attempt and can never succeed.
    private func scheduleBatchBackendRecoveryIfNeeded() {
        consecutiveSuccessfulSceneFrames = 0
        didSceneContentChangeSinceFailure = false

        guard recoveryPolicy.isEnabled, batchRenderer != nil, lastPresentationFailureKind != .permanent else {
            nextBatchRecoveryAttemptAt = nil
            return
        }

        if didDowngradeSinceHealthySceneRun {
            currentBatchRecoveryInterval = min(
                currentBatchRecoveryInterval * recoveryPolicy.backoffMultiplier,
                recoveryPolicy.maxRetryInterval
            )
        }
        didDowngradeSinceHealthySceneRun = true
        nextBatchRecoveryAttemptAt = recoveryClock() + currentBatchRecoveryInterval
    }

    /// Tries to re-attach the batch backend if we're currently on frame, the
    /// policy is enabled, and the next-attempt timestamp has passed. Success
    /// promotes us back to the scene backend; failure extends the backoff.
    private func attemptBatchBackendRecoveryIfDue(in window: Win32Window) {
        guard recoveryPolicy.isEnabled,
            activeBackend == .frame,
            let batchRenderer,
            let dueAt = nextBatchRecoveryAttemptAt
        else {
            return
        }
        let now = recoveryClock()
        guard now >= dueAt else { return }

        // The typed failure, consumed. `.sceneContent` means *this scene*
        // could not be rendered — an image that will not upload, a glyph
        // atlas that never arrived — so promoting the backend before the tree
        // has changed submits the same scene, fails the same way, and costs a
        // second visible backend switch on the way back down.
        if lastPresentationFailureKind == .sceneContent, !didSceneContentChangeSinceFailure {
            extendBatchRecoveryBackoff(now: now)
            return
        }

        let surface = surfaceDescriptor ?? surfaceDescriptorProvider(window)
        guard let surface else {
            // No surface available — schedule the next attempt and bail.
            extendBatchRecoveryBackoff(now: now)
            return
        }

        do {
            // The other half of the presenter switch: the frame backend owns
            // this HWND's swap chain right now, so it has to let go before
            // the batch backend can claim it.
            renderer.detach()
            try batchRenderer.attach(to: surface)
            try batchRenderer.resize(to: surface.pixelSize)
            activeBackend = .scene
            invalidatePresentedContentTracking()
            nextBatchRecoveryAttemptAt = nil
            // The interval is deliberately *not* reset here: a successful
            // re-attach on a healthy device says nothing about whether the
            // scene will render. `noteSuccessfulSceneFrame` retires the ladder
            // once frames actually reach the screen.
            consecutiveSuccessfulSceneFrames = 0
            lastPresentationFailureKind = nil
            didSceneContentChangeSinceFailure = false
            // A real recovery makes the suppressed failures history: the next
            // occurrence of any of them deserves a line again.
            resetFailureReporting()
            report("Batch renderer recovered after fallback.")
            updatePresentationSelection(reason: .batchBackendRecovered)
        } catch {
            lastPresentationFailureKind = PresentationFailureKind.classifying(error)
            // Recovery failed with the frame backend already released: put
            // it back so the window keeps presenting instead of freezing on
            // its last frame until the next attempt.
            batchRenderer.detach()
            do {
                try renderer.attach(to: surface)
                try renderer.resize(to: surface.pixelSize)
            } catch {
                report("Frame renderer re-attach after a failed batch recovery failed: \(error).")
            }
            extendBatchRecoveryBackoff(now: now)
            report("Batch renderer recovery attempt failed: \(error). Will retry in \(currentBatchRecoveryInterval)s.")
        }
    }

    private func extendBatchRecoveryBackoff(now: Double) {
        // A permanent capability failure never becomes possible later; stop
        // scheduling instead of burning a scene build every backoff window.
        if lastPresentationFailureKind == .permanent {
            nextBatchRecoveryAttemptAt = nil
            return
        }

        let nextInterval = min(
            currentBatchRecoveryInterval * recoveryPolicy.backoffMultiplier,
            recoveryPolicy.maxRetryInterval
        )
        currentBatchRecoveryInterval = nextInterval
        nextBatchRecoveryAttemptAt = now + nextInterval
    }

    private func updatePresentationSelection(reason: PresentationSelectionReason) {
        currentPresentationSelection = PresentationSelection(
            presenter: activeBackend == .scene ? .scene : .frame,
            reason: reason,
            frameBackend: renderer.backendDisplayName,
            sceneBackend: batchRenderer?.backendDisplayName
        )
    }

    private func completeStartupProbeIfNeeded(
        in window: Win32Window,
        success: Bool,
        errorMessage: String?
    ) {
        guard let startupProbeConfiguration, !startupProbeCompleted else {
            return
        }

        startupProbeCompleted = true

        let payload: String
        if success, let selection = currentPresentationSelection {
            payload = selection.startupProbePayload(
                logicalRootSize: currentLogicalRootSize,
                displayScale: currentDisplayScale
            )
        } else {
            let detail = (errorMessage ?? "Startup probe failed.").replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            payload = "status=failure\nmessage=\(detail)\n"
        }

        do {
            try payload.write(
                to: URL(fileURLWithPath: startupProbeConfiguration.path),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            report("Failed to write startup probe. \(error)")
        }

        if startupProbeConfiguration.shouldExitAfterProbe {
            window.requestClose()
        }
    }

    private func report(_ error: Error) {
        report(String(describing: error))
    }

    private func report(_ message: String) {
        emittedReportCount += 1
        print("[WinSwiftUI] \(message)")
    }

    /// Reports a failure that can recur every frame. `report` is synchronous
    /// console I/O on the UI thread, so a deterministic presentation failure
    /// used to add two `print`s per frame to a window that was already frozen.
    /// Each distinct signature is reported once and then only every
    /// `repeatedFailureReportInterval` recurrences, with the running count.
    private func reportRepeating(_ message: String, signature: String) {
        if let previous = reportedFailureCounts[signature] {
            let count = previous + 1
            reportedFailureCounts[signature] = count
            if count % Self.repeatedFailureReportInterval == 0 {
                report("\(message) (repeated \(count) times)")
            }
            return
        }

        guard reportedFailureCounts.count < Self.maximumTrackedFailureSignatures else {
            // Bounded: a pathological stream of distinct messages must not
            // grow the table, and must not restore per-frame logging either.
            if !didReportFailureSignatureOverflow {
                didReportFailureSignatureOverflow = true
                report("Further distinct presentation failures are being suppressed.")
            }
            return
        }

        reportedFailureCounts[signature] = 1
        report(message)
    }

    /// Clears the throttle after a genuine recovery, so the next failure of a
    /// previously-seen kind is reported again rather than silently counted.
    private func resetFailureReporting() {
        reportedFailureCounts.removeAll(keepingCapacity: true)
        didReportFailureSignatureOverflow = false
    }
}
@MainActor
private final class WindowInputRateTracker {
    private var timestamps: [TimeInterval] = []
    private let windowDuration: TimeInterval = 0.1
    private let inputsPerSecond = 60.0
    private let sustainDuration: TimeInterval = 1.0
    private var sustainUntil: TimeInterval = 0

    func recordInput(at timestamp: TimeInterval = Win32Window.currentTimestampSeconds()) {
        timestamps.append(timestamp)
        prune(before: timestamp - windowDuration)

        let minEvents = Int((inputsPerSecond * windowDuration).rounded(.down))
        if timestamps.count >= max(minEvents, 1) {
            sustainUntil = timestamp + sustainDuration
        }
    }

    var isHighRate: Bool {
        Win32Window.currentTimestampSeconds() < sustainUntil
    }

    private func prune(before threshold: TimeInterval) {
        timestamps.removeAll { $0 < threshold }
    }
}
@MainActor
public struct TimerState: Equatable, Sendable {
    /// Whether the animation timer is currently enabled.
    public let isEnabled: Bool

    /// Timer interval in milliseconds (determined by refresh rate).
    public let intervalMilliseconds: UInt32

    /// Whether high-resolution timer mode is active.
    public let usesHighResolution: Bool

    /// The refresh rate used to calculate the timer interval.
    public let refreshRate: UInt32

    public init(
        isEnabled: Bool,
        intervalMilliseconds: UInt32,
        usesHighResolution: Bool,
        refreshRate: UInt32
    ) {
        self.isEnabled = isEnabled
        self.intervalMilliseconds = intervalMilliseconds
        self.usesHighResolution = usesHighResolution
        self.refreshRate = refreshRate
    }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public protocol Widget {
    associatedtype Body: WidgetConfiguration
    var body: Body { get }
    static var supportedFamilies: [WidgetFamily] { get }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
extension Widget {
    public static var supportedFamilies: [WidgetFamily] { [.systemSmall, .systemMedium, .systemLarge] }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public protocol WidgetBundle {
    associatedtype Body: Widget
    @WidgetBundleBuilder var body: Body { get }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
@resultBuilder
public enum WidgetBundleBuilder {
    public static func buildBlock(_ widgets: any Widget...) -> any Widget {
        WidgetGroup(widgets: widgets)
    }
    public static func buildOptional(_ widget: (any Widget)?) -> any Widget {
        widget ?? WidgetGroup(widgets: [])
    }
    public static func buildEither(first widget: any Widget) -> any Widget {
        widget
    }
    public static func buildEither(second widget: any Widget) -> any Widget {
        widget
    }
    public static func buildArray(_ widgets: [any Widget]) -> any Widget {
        WidgetGroup(widgets: widgets)
    }
    public static func buildExpression(_ widget: any Widget) -> any Widget {
        widget
    }
    public static func buildLimitedAvailability(_ widget: any Widget) -> any Widget {
        widget
    }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct WidgetGroup: Widget {
    public typealias Body = Never
    public var body: Never { fatalError("WidgetGroup has no body") }
    public let widgets: [any Widget]
    public init(widgets: [any Widget]) {
        self.widgets = widgets
    }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
@preconcurrency public protocol WidgetConfiguration {
    associatedtype Body: WidgetConfiguration
    var body: Body { get }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
extension Never: @preconcurrency WidgetConfiguration {}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct StaticConfiguration<IntentType, Content: View>: WidgetConfiguration where IntentType: Intent {
    public typealias Body = Never
    public var body: Never { fatalError("StaticConfiguration has no body") }
    public init<Provider: TimelineProvider>(
        kind: String,
        provider: Provider,
        content: @escaping (Provider.Entry) -> Content
    ) {}
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct IntentConfiguration<IntentType, Content: View>: WidgetConfiguration where IntentType: Intent {
    public typealias Body = Never
    public var body: Never { fatalError("IntentConfiguration has no body") }
    public init<Provider: TimelineProvider>(
        kind: String,
        intent: IntentType.Type,
        provider: Provider,
        content: @escaping (Provider.Entry) -> Content
    ) {}
}
// AppIntentConfiguration shipped with WidgetKit on iOS 17 / macOS 14 (not macOS 17).
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct AppIntentConfiguration<IntentType, Content: View>: WidgetConfiguration where IntentType: AppIntent {
    public typealias Body = Never
    public var body: Never { fatalError("AppIntentConfiguration has no body") }
    public init<Provider: TimelineProvider>(
        kind: String,
        intent: IntentType.Type,
        provider: Provider,
        content: @escaping (Provider.Entry) -> Content
    ) {}
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public protocol AccessoryWidgetConfiguration: WidgetConfiguration {}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public protocol WidgetAccentable {
    var isWidgetAccentable: Bool { get }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public enum WidgetFamily: Sendable, Equatable, Hashable {
    case systemSmall
    case systemMedium
    case systemLarge
    case systemExtraLarge
    case accessoryInline
    case accessoryCircular
    case accessoryRectangular
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public protocol TimelineProvider {
    associatedtype Entry: TimelineEntry
    func placeholder(in context: TimelineProviderContext) -> Entry
    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (Entry) -> Void)
    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<Entry>) -> Void)
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public protocol TimelineEntry: Sendable, Equatable {
    var date: Date { get }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct Timeline<Entry: TimelineEntry>: Sendable, Equatable {
    public let entries: [Entry]
    public let policy: TimelineReloadPolicy
    public init(entries: [Entry], policy: TimelineReloadPolicy = .atEnd) {
        self.entries = entries
        self.policy = policy
    }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public enum TimelineReloadPolicy: Sendable, Equatable {
    case atEnd
    case after(Date)
    case never
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct TimelineProviderContext: Sendable, Equatable {
    public let family: WidgetFamily
    public let displaySize: Size
    public init(family: WidgetFamily, displaySize: Size) {
        self.family = family
        self.displaySize = displaySize
    }
}
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public protocol Intent: Sendable, Equatable {}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public protocol AppIntent: Sendable, Equatable {
    static var title: String { get }
    static var description: String? { get }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension AppIntent {
    public static var description: String? { nil }
}
