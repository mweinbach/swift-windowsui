import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsPlatform

import SwiftWindowsRendererD3D11

import SwiftWindowsUI

// MARK: - Timer State Observability

/// Immutable snapshot of animation timer state for observability.
/// Captures the configuration determined by `syncAnimationDriver`.

// MARK: - WidgetKit shims

@MainActor
public protocol Scene {
    associatedtype Body: Scene

    var body: Body { get }

    func makeWindowConfiguration() -> WindowGroupConfiguration
}
extension Scene {
    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        body.makeWindowConfiguration()
    }
}
extension Never: Scene {
    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        fatalError("Never cannot build a window configuration")
    }
}
@MainActor
public protocol App {
    associatedtype Body: Scene

    init()

    var body: Body { get }

    /// Override to inject a custom render backend factory.
    /// Default is ``D3D11RenderBackendFactory`` on Windows.
    static func renderBackendFactory() -> RenderBackendFactory
}
extension App {
    public static func renderBackendFactory() -> RenderBackendFactory {
        D3D11RenderBackendFactory()
    }

    public static func main() {
        let app = Self.init()
        let factory = Self.renderBackendFactory()

        do {
            let host = WinSwiftUIWindowHost(
                configuration: app.body.makeWindowConfiguration(),
                renderer: factory.makeRenderBackend(),
                batchRenderer: factory.makeBatchRenderBackend()
            )
            _ = try host.run()
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
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: content()
        )
    }

    public init(
        _ title: String = "WinSwiftUI",
        id: String,
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: content(),
            windowID: id
        )
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
    ) {
        let document = newDocument()
        let binding = Binding(get: { document }, set: { _ in })
        let fileConfig = FileDocumentConfiguration(document: binding, fileURL: nil, isEditable: true)
        self.configuration = WindowGroupConfiguration(
            title: "Untitled",
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content(fileConfig))],
            isDocumentGroup: true
        )
    }

    public init<Document: FileDocument>(
        viewing documentType: Document.Type,
        @ViewBuilder content: @escaping (FileDocumentConfiguration<Document>) -> Content
    ) {
        let document: Document
        do {
            let readConfig =
                FileDocumentReadConfiguration(file: FileWrapper(), contentType: UTType.data)
                as! Document.ReadConfiguration
            document = try documentType.init(configuration: readConfig)
        } catch {
            fatalError("DocumentGroup(viewing:) requires a document type with a default-readable init: \(error)")
        }
        let binding = Binding(get: { document }, set: { _ in })
        let fileConfig = FileDocumentConfiguration(document: binding, fileURL: nil, isEditable: false)
        self.configuration = WindowGroupConfiguration(
            title: "Untitled",
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content(fileConfig))],
            isDocumentGroup: true
        )
    }

    public init<Document: FileDocument>(
        editing documentType: Document.Type,
        @ViewBuilder content: @escaping (FileDocumentConfiguration<Document>) -> Content
    ) {
        let document: Document
        do {
            let readConfig =
                FileDocumentReadConfiguration(file: FileWrapper(), contentType: UTType.data)
                as! Document.ReadConfiguration
            document = try documentType.init(configuration: readConfig)
        } catch {
            fatalError("DocumentGroup(editing:) requires a document type with a default-readable init: \(error)")
        }
        let binding = Binding(get: { document }, set: { _ in })
        let fileConfig = FileDocumentConfiguration(document: binding, fileURL: nil, isEditable: true)
        self.configuration = WindowGroupConfiguration(
            title: "Untitled",
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content(fileConfig))],
            isDocumentGroup: true
        )
    }

    public init<Document: ReferenceFileDocument>(
        newDocument: @autoclosure @escaping () -> Document,
        @ViewBuilder content: @escaping (FileDocumentConfiguration<Document>) -> Content
    ) {
        let document = newDocument()
        let binding = Binding(get: { document }, set: { _ in })
        let fileConfig = FileDocumentConfiguration(document: binding, fileURL: nil, isEditable: true)
        self.configuration = WindowGroupConfiguration(
            title: "Untitled",
            size: IntSize(width: 1280, height: 720),
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            content: [AnyView(content(fileConfig))],
            isDocumentGroup: true
        )
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
        var configuration = content.makeWindowConfiguration()
        configuration.content = configuration.content.map { AnyView($0.environment(keyPath, value)) }
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
        var configuration = content.makeWindowConfiguration()
        configuration.content = configuration.content.map { AnyView($0.environmentObject(object)) }
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
}
public struct WindowGroupConfiguration {
    public var title: String
    public var size: IntSize
    public var clearColor: Color
    public var content: [AnyView]
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
}
enum WindowHostInputEvent {
    case pointerMoved(point: Point, scaleFactor: Double)
    case pointerExitedWindow
    case mouseWheel(point: Point, delta: Double, axis: ScrollAxis?, scaleFactor: Double)
    case pointerDown(point: Point, scaleFactor: Double)
    case pointerUp(point: Point, scaleFactor: Double)
    case contextClick(point: Point, scaleFactor: Double)
    case keyDown(KeyboardEvent)
    case keyboardFocusDidLeaveWindow
}
@MainActor
final class WinSwiftUIWindowHost: WindowDelegate {
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
    private let surfaceDescriptorProvider: @MainActor (Win32Window) -> SurfaceDescriptor?
    private let sceneRenderer: @MainActor (RetainedViewRuntime, Double) -> GPUIScene
    private let startupPresentationMode: StartupPresentationMode
    private let startupProbeConfiguration: StartupProbeConfiguration?
    private let inputRateTracker = WindowInputRateTracker()
    private let undoManager = UndoManager()

    private var isRendererReady = false
    private var activeBackend: PresentationBackend = .frame
    private var surfaceDescriptor: SurfaceDescriptor?

    /// Configured at init. When `isEnabled`, the host periodically tries to
    /// re-attach the batch backend after a downgrade.
    private let recoveryPolicy: BatchBackendRecoveryPolicy
    /// Wall-clock timestamp (seconds) of the next batch-recovery attempt, or
    /// `nil` while batch is the active backend.
    private var nextBatchRecoveryAttemptAt: Double?
    /// Current backoff interval; doubles on each failed attempt, capped at
    /// `recoveryPolicy.maxRetryInterval`.
    private var currentBatchRecoveryInterval: Double = 0
    /// Test seam: lets unit tests inject a fake wall clock without touching
    /// `Win32Window.currentTimestampSeconds`.
    var recoveryClock: @MainActor () -> Double = { Win32Window.currentTimestampSeconds() }
    private var pendingPresentation = false
    private var startupProbeCompleted = false
    private var isWindowActive = true
    private var isWindowVisible = true
    private(set) var currentPresentationSelection: PresentationSelection?

    /// Batching flag: when true, a reload has already been scheduled for the
    /// next main-actor turn and additional change notifications are coalesced.
    private var reloadScheduled = false

    /// Set of ObjectIdentifiers for which we currently hold observation tokens.
    /// Tracked so we can match incoming change notifications to the
    /// ComponentHost's dependency set and skip rebuilds for unrelated objects.
    private var observedObjectTokens: [ObjectIdentifier: ObservationToken] = [:]

    /// Accumulates the identifiers of observable objects that triggered change
    /// notifications during the current batched window.  When the deferred
    /// reload fires, only rebuild if the ComponentHost actually depends on at
    /// least one of them.
    private var pendingChangedObjects: Set<ObjectIdentifier> = []

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
    /// finishes dependency evaluation.
    /// Used for testing whether the task reloaded or was rejected.
    var onObservedObjectReloadTaskCompleted: ((_ didReload: Bool) -> Void)?

    /// Optional callback for recording timer state changes, used for testing.
    /// Called whenever `syncAnimationDriver` updates timer configuration.
    var onTimerStateChanged: ((TimerState) -> Void)?

    /// Optional callback for recording input events after the runtime consumes them.
    /// Used by host tests to prove the real WinSwiftUIWindowHost routed converted input.
    var onInputEventRouted: ((WindowHostInputEvent) -> Void)?

    /// Current timer state for observability. Updated by `syncAnimationDriver`.
    private(set) var currentTimerState: TimerState = TimerState(
        isEnabled: false,
        intervalMilliseconds: 16,
        usesHighResolution: false,
        refreshRate: 60
    )

    init(
        configuration: WindowGroupConfiguration,
        renderer: any RenderBackend = DefaultRenderBackendFactory.make(),
        batchRenderer: (any BatchRenderBackend)? = DefaultRenderBackendFactory.makeBatchBackend(),
        surfaceDescriptorProvider: @escaping @MainActor (Win32Window) -> SurfaceDescriptor? = WinSwiftUIWindowHost
            .defaultSurfaceDescriptor,
        sceneRenderer: (@MainActor (RetainedViewRuntime, Double) -> GPUIScene)? = nil,
        startupPresentationMode: StartupPresentationMode = .fromEnvironment(),
        startupProbeConfiguration: StartupProbeConfiguration? = .fromEnvironment(),
        recoveryPolicy: BatchBackendRecoveryPolicy = .disabled
    ) {
        self.configuration = configuration
        self.window = Win32Window(
            title: configuration.title, clientSize: configuration.size,
            titleBarVisibility: configuration.titleBarVisibility ?? .automatic)
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

        runtime.setRootSize(configuration.size)
        componentHost.setComponents { [weak self] in
            guard let self else {
                return []
            }

            return [self.buildRootComponent()]
        }
        window.delegate = self
    }

    @discardableResult
    func run() throws -> Int32 {
        try Win32Application.run(window: window)
    }

    func windowDidCreate(_ window: Win32Window) {
        do {
            guard let surface = surfaceDescriptorProvider(window) else {
                completeStartupProbeIfNeeded(in: window, success: false, errorMessage: "Missing surface descriptor.")
                return
            }

            surfaceDescriptor = surface
            try attachPreferredRenderer(to: surface)
            isRendererReady = true
            runtime.displayScale = surface.scaleFactor
            runtime.setRootSize(logicalSize(for: surface))
            componentHost.reload()
            let didRender = renderCurrentFrame(in: window)
            completeStartupProbeIfNeeded(
                in: window,
                success: didRender,
                errorMessage: didRender ? nil : "Initial startup render did not complete."
            )
        } catch {
            completeStartupProbeIfNeeded(in: window, success: false, errorMessage: String(describing: error))
            report(error)
        }
    }

    func window(_ window: Win32Window, didResizeTo size: IntSize) {
        do {
            let scaleFactor = window.scaleFactor
            runtime.displayScale = scaleFactor
            surfaceDescriptor?.pixelSize = size
            surfaceDescriptor?.scaleFactor = scaleFactor
            runtime.setRootSize(logicalSize(for: size, scaleFactor: scaleFactor))
            componentHost.reload()
            try resizeActiveRenderer(to: size, in: window)
            requestFrame(in: window)
        } catch {
            report(error)
        }
    }

    func windowNeedsDisplay(_ window: Win32Window) {
        _ = renderCurrentFrame(in: window)
    }

    func window(_ window: Win32Window, pointerMovedTo point: Point) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerMoved(to: logicalPoint)
        onInputEventRouted?(.pointerMoved(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func windowPointerDidLeave(_ window: Win32Window) {
        runtime.pointerExitedWindow()
        onInputEventRouted?(.pointerExitedWindow)
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.mouseWheel(at: logicalPoint, delta: delta)
        onInputEventRouted?(.mouseWheel(point: logicalPoint, delta: delta, axis: nil, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, horizontalScrollAt point: Point, delta: Double) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.mouseWheel(at: logicalPoint, delta: delta, axis: .horizontal)
        onInputEventRouted?(.mouseWheel(point: logicalPoint, delta: delta, axis: .horizontal, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerDown(at: logicalPoint)
        onInputEventRouted?(.pointerDown(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerUp(at: logicalPoint)
        onInputEventRouted?(.pointerUp(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func windowDidReceiveRightClick(_ window: Win32Window, event: MouseEvent) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(event.position, scaleFactor: scaleFactor)
        runtime.contextClick(at: logicalPoint)
        onInputEventRouted?(.contextClick(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
        runtime.keyDown(event)
        onInputEventRouted?(.keyDown(event))
        commitRuntimeState(in: window, interactive: true)
    }

    func windowDidLoseKeyboardFocus(_ window: Win32Window) {
        runtime.keyboardFocusDidLeaveWindow()
        onInputEventRouted?(.keyboardFocusDidLeaveWindow)
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, animationFrameAt timestamp: Double) {
        let didAdvanceAnimations = runtime.tickAnimations(at: timestamp)
        if didAdvanceAnimations || runtime.isDirty || pendingPresentation {
            _ = renderCurrentFrame(in: window, timestamp: timestamp)
        } else {
            syncAnimationDriver(for: window)
        }
    }

    func windowDidChangeDisplay(_ window: Win32Window) {
        syncAnimationDriver(for: window)
    }

    func windowDidChangeSystemSettings(_ window: Win32Window) {
        syncAnimationDriver(for: window)
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

    func windowWillClose(_ window: Win32Window) {}

    private var buildContext: ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { [weak self] in
                self?.runtime.root.frame.size
                    ?? Size(
                        width: Double(self?.configuration.size.width ?? 0),
                        height: Double(self?.configuration.size.height ?? 0)
                    )
            },
            invalidateHandler: { [weak self] in
                self?.reloadContent()
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
                    displayScale: displayScale,
                    pixelLength: Self.pixelLength(for: displayScale),
                    horizontalSizeClass: self?.resolvedHorizontalSizeClass ?? .regular,
                    verticalSizeClass: self?.resolvedVerticalSizeClass ?? .regular,
                    undoManager: self?.undoManager
                )
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
        composeComponent(from: configuration.content, context: buildContext)
    }

    private func reloadContent() {
        executedReloadCount += 1

        // Record the objects the ComponentHost accesses during this rebuild
        // so future notifications can be dependency-checked.
        componentHost.observedObjects.removeAll()
        resetObservedObjects()
        componentHost.reload()

        // Present any file-importer / exporter / mover dialogs whose
        // isPresented binding has been set to true.
        componentHost.processPendingFileDialogs()

        // After rebuild, snapshot which objects were observed.
        for identifier in observedObjectTokens.keys {
            componentHost.observedObjects.insert(identifier)
        }

        onReloadContentCompleted?()
        commitRuntimeState(in: window)
    }

    /// Manually observe an object for testing purposes.
    /// This allows tests to register observed objects without needing a view hierarchy.
    func observe(_ object: any ObservableObject) {
        observeObject(object)
    }

    private func observeObject(_ object: any ObservableObject) {
        let identifier = ObjectIdentifier(object)
        guard observedObjectTokens[identifier] == nil else {
            return
        }

        observedObjectRegistrationCount += 1
        onObservedObjectRegistered?(identifier)

        observedObjectTokens[identifier] = ObservableObjectCenter.shared.addObserver(for: object) { [weak self] in
            self?.scheduleObservedObjectReload(for: identifier)
        }
    }

    private func resetObservedObjects() {
        let tokens = Array(observedObjectTokens.values)
        observedObjectTokens.removeAll()
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
            activeBackendDisplayName: activeBackendName
        )
    }

    /// Schedule a batched reload.  Multiple rapid @Published changes within
    /// the same run-loop turn are coalesced into a single rebuild.
    ///
    /// Additionally, when the deferred reload fires, we check whether the
    /// ComponentHost actually depends on any of the objects that changed.  If
    /// none of the changed objects are in the host's dependency set, the
    /// rebuild is skipped entirely.
    private func scheduleObservedObjectReload(for changedObjectID: ObjectIdentifier) {
        pendingChangedObjects.insert(changedObjectID)
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

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.reloadScheduled = false

            // Dependency tracking: only rebuild if the ComponentHost actually
            // observed at least one of the changed objects.
            let relevantChanges = self.pendingChangedObjects
            self.pendingChangedObjects.removeAll()

            let dependsOnChangedObject =
                self.componentHost.observedObjects.isEmpty
                || !relevantChanges.isDisjoint(with: self.componentHost.observedObjects)

            guard dependsOnChangedObject else {
                // Dependency filtering: none of the changed objects are in our dependency set
                // Skip the reload entirely
                self.skippedObservedObjectReloadCount += 1
                self.completedObservedObjectReloadTaskCount += 1
                self.onObservedObjectReloadTaskCompleted?(false)
                return
            }

            self.reloadContent()
            self.completedObservedObjectReloadTaskCount += 1
            self.onObservedObjectReloadTaskCompleted?(true)
        }
    }

    private func commitRuntimeState(in window: Win32Window, interactive: Bool = false) {
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
        let wasPending = pendingPresentation
        pendingPresentation = true
        syncAnimationDriver(for: window)
        if !wasPending {
            window.invalidate()
        }
    }

    @discardableResult
    private func renderCurrentFrame(in window: Win32Window, timestamp: Double? = nil) -> Bool {
        guard isRendererReady else {
            if runtime.isDirty || pendingPresentation {
                window.invalidate()
            }
            return false
        }

        // Opportunistic recovery: if we previously downgraded and the
        // configured policy permits, try re-attaching the batch backend
        // before this frame's render path picks a backend.
        attemptBatchBackendRecoveryIfDue(in: window)

        guard runtime.isDirty || pendingPresentation || runtime.hasActiveAnimations || inputRateTracker.isHighRate
        else {
            syncAnimationDriver(for: window)
            return false
        }

        do {
            if activeBackend == .scene, let batchRenderer {
                let scene = sceneRenderer(runtime, timestamp ?? 0)
                batchRenderer.bindResources(for: scene)
                try batchRenderer.render(scene: scene)
            } else {
                try renderer.render(frame: runtime.renderFrame(at: timestamp ?? 0))
            }
        } catch {
            guard activeBackend == .scene else {
                report(error)
                return false
            }

            do {
                try fallbackToFrameRenderer(
                    becauseOf: .batchRenderFailure(String(describing: error)),
                    in: window
                )
                try renderer.render(frame: runtime.renderFrame(at: timestamp ?? 0))
            } catch {
                report(error)
                return false
            }
        }

        pendingPresentation = runtime.isDirty || runtime.hasActiveAnimations || inputRateTracker.isHighRate
        syncAnimationDriver(for: window)
        return true
    }

    private func syncAnimationDriver(for window: Win32Window) {
        let refreshRate = max(Int(window.monitorRefreshRate), 1)
        runtime.minimumFrameInterval = 1.0 / Double(refreshRate)
        window.useHighResolutionTimer = true
        let intervalMilliseconds = UInt32(max(1, Int((1000.0 / Double(refreshRate)).rounded())))
        let shouldDriveFrames =
            runtime.hasActiveAnimations || runtime.isDirty || pendingPresentation || inputRateTracker.isHighRate
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

    private func logicalSize(for pixelSize: IntSize, scaleFactor: Double) -> IntSize {
        let logicalScale = max(scaleFactor, 1.0)
        return IntSize(
            width: Int32((Double(pixelSize.width) / logicalScale).rounded(.toNearestOrAwayFromZero)),
            height: Int32((Double(pixelSize.height) / logicalScale).rounded(.toNearestOrAwayFromZero))
        )
    }

    private func logicalPoint(_ point: Point, scaleFactor: Double) -> Point {
        guard scaleFactor > 0 else {
            return point
        }

        return Point(x: point.x / scaleFactor, y: point.y / scaleFactor)
    }

    private static func defaultSurfaceDescriptor(for window: Win32Window) -> SurfaceDescriptor? {
        guard let handle = window.nativeHandle else {
            return nil
        }

        return SurfaceDescriptor(
            windowHandle: handle,
            pixelSize: window.currentClientSize(),
            scaleFactor: window.scaleFactor
        )
    }

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
                report("Batch renderer attach failed; falling back to frame renderer. \(error)")
                try renderer.attach(to: surface)
                activeBackend = .frame
                updatePresentationSelection(reason: .batchAttachFailure(String(describing: error)))
                return
            }
        }

        try renderer.attach(to: surface)
        activeBackend = .frame
        updatePresentationSelection(reason: .batchRendererUnavailable)
    }

    private func resizeActiveRenderer(to size: IntSize, in window: Win32Window) throws {
        if activeBackend == .scene, let batchRenderer {
            do {
                try batchRenderer.resize(to: size)
                return
            } catch {
                try fallbackToFrameRenderer(
                    becauseOf: .batchResizeFailure(String(describing: error)),
                    in: window
                )
            }
        }

        try renderer.resize(to: size)
    }

    private func fallbackToFrameRenderer(
        becauseOf reason: PresentationSelectionReason,
        in window: Win32Window
    ) throws {
        if let detail = reason.detail {
            report("Batch renderer failed; switching to frame renderer. \(detail)")
        } else {
            report("Batch renderer failed; switching to frame renderer.")
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
        try renderer.attach(to: surface)
        try renderer.resize(to: surface.pixelSize)
        activeBackend = .frame
        isRendererReady = true
        updatePresentationSelection(reason: reason)
        scheduleBatchBackendRecoveryIfNeeded()
    }

    /// After a downgrade, if the recovery policy is enabled, set the next
    /// attempt timestamp. Resets backoff so the first retry happens after
    /// `initialRetryInterval`.
    private func scheduleBatchBackendRecoveryIfNeeded() {
        guard recoveryPolicy.isEnabled, batchRenderer != nil else {
            nextBatchRecoveryAttemptAt = nil
            return
        }
        currentBatchRecoveryInterval = recoveryPolicy.initialRetryInterval
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

        let surface = surfaceDescriptor ?? surfaceDescriptorProvider(window)
        guard let surface else {
            // No surface available — schedule the next attempt and bail.
            extendBatchRecoveryBackoff(now: now)
            return
        }

        do {
            try batchRenderer.attach(to: surface)
            try batchRenderer.resize(to: surface.pixelSize)
            activeBackend = .scene
            nextBatchRecoveryAttemptAt = nil
            currentBatchRecoveryInterval = recoveryPolicy.initialRetryInterval
            report("Batch renderer recovered after fallback.")
            updatePresentationSelection(reason: .batchBackendRecovered)
        } catch {
            extendBatchRecoveryBackoff(now: now)
            report("Batch renderer recovery attempt failed: \(error). Will retry in \(currentBatchRecoveryInterval)s.")
        }
    }

    private func extendBatchRecoveryBackoff(now: Double) {
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
        print("[WinSwiftUI] \(error)")
    }

    private func report(_ message: String) {
        print("[WinSwiftUI] \(message)")
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
    public static func buildBlock(_ widgets: Widget...) -> Widget {
        WidgetGroup(widgets: widgets)
    }
    public static func buildOptional(_ widget: Widget?) -> Widget {
        widget ?? WidgetGroup(widgets: [])
    }
    public static func buildEither(first widget: Widget) -> Widget {
        widget
    }
    public static func buildEither(second widget: Widget) -> Widget {
        widget
    }
    public static func buildArray(_ widgets: [Widget]) -> Widget {
        WidgetGroup(widgets: widgets)
    }
    public static func buildExpression(_ widget: Widget) -> Widget {
        widget
    }
    public static func buildLimitedAvailability(_ widget: Widget) -> Widget {
        widget
    }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct WidgetGroup: Widget {
    public typealias Body = Never
    public var body: Never { fatalError("WidgetGroup has no body") }
    public let widgets: [Widget]
    public init(widgets: [Widget]) {
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
    public init(kind: String, provider: TimelineProvider, content: @escaping (TimelineEntry) -> Content) {}
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct IntentConfiguration<IntentType, Content: View>: WidgetConfiguration where IntentType: Intent {
    public typealias Body = Never
    public var body: Never { fatalError("IntentConfiguration has no body") }
    public init(
        kind: String, intent: IntentType.Type, provider: TimelineProvider, content: @escaping (TimelineEntry) -> Content
    ) {}
}
@available(macOS 17.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct AppIntentConfiguration<IntentType, Content: View>: WidgetConfiguration where IntentType: AppIntent {
    public typealias Body = Never
    public var body: Never { fatalError("AppIntentConfiguration has no body") }
    public init(
        kind: String, intent: IntentType.Type, provider: TimelineProvider, content: @escaping (TimelineEntry) -> Content
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
