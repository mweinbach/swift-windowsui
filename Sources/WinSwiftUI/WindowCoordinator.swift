import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import SwiftWindowsUI

// MARK: - Multi-window coordinator (Phase 5)

/// Injectable OS-touching seam for `WinSwiftUIWindowCoordinator`, mirroring
/// the repo's provider pattern (SystemAppearanceProvider, FileDialogProvider,
/// UIA bridge): the default drives real Win32 window management; tests
/// substitute headless fakes.
struct WindowCoordinatorHooks {
    /// Realizes a host's window (create + show) without entering the message
    /// loop.
    var startWindow: @MainActor (WinSwiftUIWindowHost) throws -> Void

    /// Requests an OS-level close of the host's window. The close completes
    /// asynchronously via `windowWillClose` on the host (`WM_DESTROY`), which
    /// is what actually tears the window down.
    var requestCloseWindow: @MainActor (WinSwiftUIWindowHost) -> Void

    /// Runs the process message loop after the primary window has started.
    var runMessageLoop: @MainActor () throws -> Int32

    /// Posts the quit message so the message loop returns. Called when the
    /// last managed window has closed.
    var terminateMessageLoop: @MainActor () -> Void

    /// Shows or restores an existing window and asks Windows to activate it.
    /// A false result means the OS declined foreground activation, not that
    /// the scene should be duplicated. Tests can record the request without
    /// creating a native window.
    var activateWindow: @MainActor (WinSwiftUIWindowHost) -> Bool = { host in
        host.platformWindow.activate()
    }

    /// Startup rollback has already released the host's resources and removed
    /// its coordinator record. It is not an ordinary dismiss request and must
    /// not be vetoed by any installed delegate or view policy.
    var discardFailedWindow: @MainActor (WinSwiftUIWindowHost) -> Void = { host in
        host.platformWindow.destroyForFailedStartup()
    }

    /// The real Win32 hooks used by `App.main()`.
    static let win32 = WindowCoordinatorHooks(
        startWindow: { host in
            try host.validateNativeActivation()
            // The coordinator decides when the process quits; individual
            // windows must not post WM_QUIT on destroy.
            host.platformWindow.postsQuitMessageOnDestroy = false
            try Win32Application.start(window: host.platformWindow)
        },
        requestCloseWindow: { host in
            host.platformWindow.requestClose()
        },
        runMessageLoop: {
            try Win32Application.runMessageLoop()
        },
        terminateMessageLoop: {
            Win32Application.terminateMessageLoop()
        }
    )

    /// Routes native startup and event-loop ownership through the same
    /// platform factory that created each managed window.
    @MainActor
    static func platform(_ factory: any PlatformHostFactory) -> WindowCoordinatorHooks {
        WindowCoordinatorHooks(
            startWindow: { host in
                try host.validateNativeActivation()
                // The coordinator owns the last-window quit policy; individual
                // Win32 windows must not terminate the process on their own.
                host.platformWindow.postsQuitMessageOnDestroy = false
                try factory.start(window: host.platformWindow)
            },
            requestCloseWindow: { host in
                host.platformWindow.requestClose()
            },
            runMessageLoop: {
                try factory.runEventLoop()
            },
            terminateMessageLoop: {
                factory.terminateEventLoop()
            }
        )
    }
}

/// The production owner's operations complete only after their native result
/// is known. This separate seam also permits deterministic, headless tests;
/// the legacy synchronous hooks keep their original contract.
struct WindowCoordinatorNativeHooks {
    var startOwner: @MainActor () async throws -> Void
    var startWindow: @MainActor (WinSwiftUIWindowHost) async throws -> Void
    var activateWindow: @MainActor (WinSwiftUIWindowHost) async throws -> Bool
    var requestCloseWindow: @MainActor (WinSwiftUIWindowHost) -> Void
    var discardFailedWindow: @MainActor (WinSwiftUIWindowHost) async throws -> Void
    var stopOwner: @MainActor () async throws -> Int32

    @MainActor
    static func win32(_ pump: Win32NativePump) -> WindowCoordinatorNativeHooks {
        WindowCoordinatorNativeHooks(
            startOwner: { try await pump.start() },
            startWindow: { host in
                try host.validateNativeActivation()
                host.platformWindow.postsQuitMessageOnDestroy = false
                try await host.startNative(on: pump)
                _ = try await host.platformWindow.activateNative()
                try await host.finishNativeStartupPresentation()
            },
            activateWindow: { host in try await host.platformWindow.activateNative() },
            requestCloseWindow: { host in host.platformWindow.requestClose() },
            discardFailedWindow: { host in try await host.discardNativeFailedStartup() },
            stopOwner: {
                let result = try await pump.stop()
                guard result.joined else {
                    throw NativeWindowOwnerFailure.execution("The native owner returned without a thread join.")
                }
                return result.exitCode
            }
        )
    }
}

enum NativeWindowCoordinatorError: Error, CustomStringConvertible {
    case asynchronousOwnerRequired
    case alreadyRunning
    case ownerNotStarted
    case reentrantWindowPreparation
    case startupAndCleanup(startup: any Error, cleanup: any Error)

    var description: String {
        switch self {
        case .asynchronousOwnerRequired:
            return "This coordinator requires the asynchronous native-owner entry point."
        case .alreadyRunning:
            return "The native window coordinator has already started."
        case .ownerNotStarted:
            return "The native window owner has not started."
        case .reentrantWindowPreparation:
            return "A native window is already being prepared by this actor call."
        case .startupAndCleanup(let startup, let cleanup):
            return "Native startup failed: \(startup). Native cleanup also failed: \(cleanup)."
        }
    }
}

enum WindowCoordinatorError: Error, LocalizedError, Equatable, CustomStringConvertible {
    case noLaunchableWindowScene
    case nativeDocumentActivationUnavailable
    case documentServicesRequireInjectedHost
    case documentContextMismatch
    case noDocumentScene
    case documentInputRequired
    case unsupportedDocumentExtension(String)
    case unsupportedDocumentContentTypes
    case documentOperationBusy
    case windowClosedDuringStartup
    case coordinatorTerminated

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .noLaunchableWindowScene:
            return
                "The app declares no launchable window scene. Settings opens on demand; MenuBarExtra hosting is unsupported."
        case .nativeDocumentActivationUnavailable:
            return "Native document windows require a verified final close check and owned deferred delivery."
        case .documentServicesRequireInjectedHost:
            return "Headless document services require explicitly injected window hooks and a host factory."
        case .documentContextMismatch:
            return "The window did not install the document context prepared for this open request."
        case .noDocumentScene:
            return "The app declares no matching document scene."
        case .documentInputRequired:
            return "This document scene requires an existing file URL."
        case .unsupportedDocumentExtension(let fileExtension):
            return "This document stage cannot open the file extension '\(fileExtension)'."
        case .unsupportedDocumentContentTypes:
            return "This document stage requires a declared plain-text or UTF-8 plain-text content type."
        case .documentOperationBusy:
            return "The document already has an operation in progress."
        case .windowClosedDuringStartup:
            return "The window closed before startup completed."
        case .coordinatorTerminated:
            return "The window coordinator has already terminated."
        }
    }
}

/// Hosts every live window and the on-demand Settings scene of a running
/// `WinSwiftUI.App`.
///
/// Each window gets its own `WinSwiftUIWindowHost` — and therefore its own
/// `Win32Window`, `RetainedViewRuntime`, renderer attachment, UIA bridge, and
/// scene-storage scope. Retained UI and routing stay on the main actor. The
/// production path has a separate native window and presentation owner.
///
/// Close policy: closing a window tears down only that window's host —
/// `WinSwiftUIWindowHost.windowWillClose` disconnects UIA and calls
/// `detach()` on both render backends, which releases the swap chain while
/// the HWND is still alive. When the last managed window closes, the
/// coordinator terminates the message loop, matching the historical
/// single-window quit behavior.
@MainActor
final class WinSwiftUIWindowCoordinator {
    private struct DocumentRoutingRequest {
        let id: UUID
        let caller: DocumentWindowContext?
        let ticket: DocumentWindowContext.RoutingTicket?
    }

    /// A live window: its host, the configuration it presented, and the
    /// value it was opened with (for value-based `WindowGroup` scenes).
    struct ManagedWindow {
        let host: WinSwiftUIWindowHost
        let configuration: WindowGroupConfiguration
        let presentedValue: AnyHashable?
        let isPrimary: Bool
    }

    /// Ordered scene templates declared by the app body. Settings and
    /// MenuBarExtra configurations do not become the initial app window.
    private let sceneConfigurations: [WindowGroupConfiguration]
    private let hooks: WindowCoordinatorHooks
    private let nativeHooks: WindowCoordinatorNativeHooks?
    private let hostFactory: @MainActor (WindowGroupConfiguration, Bool) throws -> WinSwiftUIWindowHost
    private let sceneStorageScopeProvider: @MainActor () -> String
    private let documentServices: DocumentWindowServices?
    private let hasInjectedDocumentHost: Bool
    private var documentRoutingOperation: UUID?

    private(set) var windows: [ManagedWindow] = []
    private var isTerminated = false
    private var lastManagedCloseID: UUID?

    private var nativeRunStarted = false
    private var nativeOwnerStarted = false
    private var nativeWindowPreparation: UUID?
    private var failedNativeUnadmittedHosts: [ObjectIdentifier: WinSwiftUIWindowHost] = [:]
    private var nativeActivationResults: [ObjectIdentifier: Bool] = [:]
    private var nativeStartupTask: Task<Void, Never>?
    private var nativeStartupWaiter: CheckedContinuation<Void, any Error>?
    private var nativeWindowStarts: [ObjectIdentifier: Task<WinSwiftUIWindowHost, any Error>] = [:]
    private var nativeStartupRollbacks: Set<ObjectIdentifier> = []
    private var nativePrimaryClosedDuringStartup = false
    private var nativePendingCloseRequests: Set<ObjectIdentifier> = []
    private var nativeStopTask: Task<Int32, any Error>?
    private var nativeDiagnosticsDrain: Task<Void, Never>?
    private var nativeFatalResult: Task<Int32, any Error>?
    private var nativeStopWaiters: [CheckedContinuation<Task<Int32, any Error>, Never>] = []
    /// A failed native cleanup remains owned and visible; it is not reported
    /// as a successfully closed window or allowed to trigger a normal quit.
    private(set) var nativeLifecycleFailures: [String] = []

    /// Set when the process was launched in `--diagnostics` mode. The session
    /// attaches to the primary window only: a secondary window opened by the
    /// scripted run would otherwise start a second measurement of the same
    /// process and race the first one's report file.
    private let liveDiagnosticsConfiguration: LiveDiagnosticsConfiguration?
    private var liveDiagnosticsSession: LiveDiagnosticsSession?

    /// Hosts whose window has closed but whose deallocation is deferred.
    ///
    /// `windowDidClose` runs inside the wndproc frame that is handling
    /// `WM_DESTROY`: dropping the last strong reference there deallocates the
    /// host — and with it the runtime, the UIA bridge and both render
    /// backends — while Windows is still delivering messages to the window
    /// that owns them. The bookkeeping (and the last-window quit policy) stays
    /// immediate; only the release is held over until the next close, the next
    /// open, or the next main-actor turn, whichever comes first.
    private var hostsPendingRelease: [WinSwiftUIWindowHost] = []

    var windowCount: Int {
        windows.count
    }

    init(
        sceneConfigurations: [WindowGroupConfiguration],
        // Default: the software presenter, not `CPURenderBackendFactory`.
        // `App.main()` always passes the app's resolved factory explicitly, so
        // this only serves direct coordinator users — and for them a backend
        // that rasterizes into memory without ever blitting would open a real
        // window that shows nothing while reporting itself healthy.
        renderBackendFactory: RenderBackendFactory = SoftwareWindowRenderBackendFactory(),
        backendResolution: RenderBackendResolution? = nil,
        platformHostFactory: any PlatformHostFactory = Win32PlatformHostFactory(),
        hooks: WindowCoordinatorHooks? = nil,
        nativeHooks: WindowCoordinatorNativeHooks? = nil,
        nativePresentationFactory: (any NativePresentationBackendFactory)? = nil,
        hostFactory: (@MainActor (WindowGroupConfiguration, Bool) throws -> WinSwiftUIWindowHost)? = nil,
        sceneStorageScopeProvider: (@MainActor () -> String)? = nil,
        liveDiagnostics: LiveDiagnosticsConfiguration? = nil,
        documentServices: DocumentWindowServices? = nil
    ) {
        self.sceneConfigurations = sceneConfigurations
        self.documentServices = documentServices
        self.hasInjectedDocumentHost = hooks != nil && hostFactory != nil
        self.hooks = hooks ?? .platform(platformHostFactory)
        self.nativeHooks = nativeHooks
        self.liveDiagnosticsConfiguration = liveDiagnostics
        self.hostFactory =
            hostFactory
            ?? { configuration, isPrimary in
                let windowConfiguration = WinSwiftUIWindowHost.platformWindowConfiguration(for: configuration)
                let platformWindow = try platformHostFactory.makeWindow(configuration: windowConfiguration)
                guard let win32Window = platformWindow as? Win32Window else {
                    throw PlatformHostError.incompatibleWindow(
                        expectedPlatform: Win32PlatformHostFactory().platformName
                    )
                }
                if nativePresentationFactory != nil {
                    guard win32Window.nativeHandle == nil, !win32Window.usesNativeOwner else {
                        throw NativeWindowOwnerFailure.execution(
                            "A native platform factory must return an uncreated, unowned window facade."
                        )
                    }
                }

                return WinSwiftUIWindowHost(
                    configuration: configuration,
                    platformWindow: win32Window,
                    renderer: renderBackendFactory.makeRenderBackend(),
                    batchRenderer: renderBackendFactory.makeBatchRenderBackend(),
                    nativePresentationFactory: nativePresentationFactory,
                    // Only the primary window writes the startup probe;
                    // secondary windows must not overwrite it on open.
                    startupProbeConfiguration: isPrimary ? .fromEnvironment() : nil,
                    backendResolution: backendResolution,
                    // Real windows remember the pacing watchdog's verdict
                    // across sessions, so a launch on a compositor that was
                    // broken yesterday starts self-paced instead of replaying
                    // the 1.5 s evidence slideshow. Hosts built directly
                    // (tests, embedders) default to no memory.
                    presentPacingMemory: .standard
                )
            }
        self.sceneStorageScopeProvider =
            sceneStorageScopeProvider ?? { "window:\(UUID().uuidString)" }
    }

    /// Creates and starts the primary window, then runs the message loop.
    /// Behaviorally identical to the historical single-window `App.main()`
    /// boot when only one window is ever opened.
    @discardableResult
    func run() throws -> Int32 {
        guard nativeHooks == nil else { throw NativeWindowCoordinatorError.asynchronousOwnerRequired }
        try bootPrimaryWindow()
        return try hooks.runMessageLoop()
    }

    /// Creates the primary host/window and starts it without entering the
    /// message loop. Internal so headless tests can drive the coordinator
    /// without a real run loop.
    @discardableResult
    func bootPrimaryWindow() throws -> WinSwiftUIWindowHost {
        guard nativeHooks == nil else { throw NativeWindowCoordinatorError.asynchronousOwnerRequired }
        if let primary = windows.first(where: \.isPrimary) {
            return primary.host
        }

        guard let configuration = sceneConfigurations.first(where: { !$0.isSettingsWindow && !$0.isMenuBarExtra })
        else {
            throw WindowCoordinatorError.noLaunchableWindowScene
        }

        if configuration.isDocumentGroup {
            return try withDocumentRouting(from: nil, configuration: configuration) { template, services, request in
                try self.makeNewDocument(
                    configuration: template, services: services, isPrimary: true, request: request
                )
            }
        }

        return try openManagedWindow(
            configuration: configuration,
            presentedValue: nil,
            isPrimary: true
        )
    }

    /// Default `openWindow` routing: finds the scene template matching the
    /// requested id and/or value type and opens a new window hosting its
    /// content. Value-based re-presentation of an already-open value
    /// re-uses the existing window instead of duplicating it. Returns false
    /// when no scene matches.
    @discardableResult
    func openWindow(payload: WindowActionPayload) -> Bool {
        guard nativeHooks == nil else { return false }
        guard payload.id != nil || payload.value != nil else {
            return false
        }

        guard
            let template = sceneConfigurations.first(where: { template in
                guard !template.isSettingsWindow && !template.isMenuBarExtra && !template.isDocumentGroup else {
                    return false
                }
                if let id = payload.id, template.windowID != id {
                    return false
                }
                if let value = payload.value {
                    guard template.forType == type(of: value.base), template.dataBoundContent != nil else {
                        return false
                    }
                }
                return true
            })
        else {
            return false
        }

        if let value = payload.value,
            let existing = windows.first(where: {
                $0.configuration.windowID == template.windowID && $0.presentedValue == value
            })
        {
            // SwiftUI re-presents the existing window for an already-open
            // value rather than opening a duplicate. Windows may decline a
            // foreground request; that still must not duplicate the scene.
            _ = hooks.activateWindow(existing.host)
            return true
        }

        var configuration = template
        if let value = payload.value, let dataBoundContent = template.dataBoundContent {
            configuration.content = dataBoundContent(value)
        }

        do {
            try openManagedWindow(configuration: configuration, presentedValue: payload.value, isPrimary: false)
            return true
        } catch {
            print("[WinSwiftUI] Failed to open window: \(error)")
            return false
        }
    }

    /// Internal operations behind the existing environment actions. They use
    /// document declarations directly, never AnyHashable value-window routing.
    @discardableResult
    func newDocument(from caller: DocumentWindowContext? = nil) throws -> WinSwiftUIWindowHost {
        try withDocumentRouting(from: caller) { template, services, request in
            try self.makeNewDocument(
                configuration: template, services: services, isPrimary: false, request: request
            )
        }
    }

    @discardableResult
    func openDocument(at url: URL, from caller: DocumentWindowContext? = nil) throws -> WinSwiftUIWindowHost {
        try withDocumentRouting(from: caller) { template, services, request in
            try self.openDocument(at: url, configuration: template, services: services, request: request)
        }
    }

    /// Nil means the user cancelled selection. Errors retain their identity
    /// and are presented only by the still-current requesting document.
    @discardableResult
    func chooseOpenDocument(from caller: DocumentWindowContext) throws -> WinSwiftUIWindowHost? {
        try withDocumentRouting(from: caller) { template, services, request in
            guard let descriptor = template.documentScene else { throw WindowCoordinatorError.noDocumentScene }
            try descriptor.validateDocumentType()
            try self.validate(request)
            let types = descriptor.readableContentTypes()
            try self.validate(request)
            let type = try Self.plainTextType(in: types)
            let owner = caller.owner.dialogOwner()
            try self.validate(request)
            let result = services.files.chooseOpenURL(types: [type], owner: owner)
            try self.validate(request)
            switch result {
            case .selected(let url):
                return try self.openDocument(
                    at: url, configuration: template, services: services, request: request
                )
            case .cancelled:
                return nil
            case .failed(let error):
                throw error
            }
        }
    }

    private func withDocumentRouting<Result>(
        from caller: DocumentWindowContext?,
        configuration: WindowGroupConfiguration? = nil,
        perform: (WindowGroupConfiguration, DocumentWindowServices, DocumentRoutingRequest) throws -> Result
    ) throws -> Result {
        // These checks precede every model factory, content-type getter and
        // file read, including a directly booted DocumentGroup declaration.
        guard let services = documentServices else {
            throw WindowCoordinatorError.nativeDocumentActivationUnavailable
        }
        guard hasInjectedDocumentHost else { throw WindowCoordinatorError.documentServicesRequireInjectedHost }
        guard !isTerminated else { throw WindowCoordinatorError.coordinatorTerminated }
        guard documentRoutingOperation == nil else { throw WindowCoordinatorError.documentOperationBusy }
        guard
            let template = configuration
                ?? sceneConfigurations.first(where: {
                    $0.isDocumentGroup && !$0.isSettingsWindow && !$0.isMenuBarExtra
                        && (caller == nil || $0.documentScene?.id == caller?.descriptor.id)
                }), template.isDocumentGroup, template.documentScene != nil
        else {
            throw WindowCoordinatorError.noDocumentScene
        }
        if let caller {
            guard caller.owner.isValid,
                windows.contains(where: { $0.host === caller.host && $0.configuration.documentWindowContext === caller }
                )
            else { throw DocumentSessionError.ownerUnavailable }
        }

        let requestID = UUID()
        documentRoutingOperation = requestID
        let ticket: DocumentWindowContext.RoutingTicket?
        do {
            ticket = try caller?.beginRouting()
        } catch {
            if documentRoutingOperation == requestID { documentRoutingOperation = nil }
            throw error
        }
        let request = DocumentRoutingRequest(id: requestID, caller: caller, ticket: ticket)
        defer {
            if documentRoutingOperation == request.id { documentRoutingOperation = nil }
            if let caller, let ticket { caller.finishRouting(ticket) }
        }
        do {
            try validate(request)
            let result = try perform(template, services, request)
            try validate(request)
            return result
        } catch {
            if (try? validate(request)) != nil {
                caller?.reportRoutingError(error)
            }
            throw error
        }
    }

    private func validate(_ request: DocumentRoutingRequest) throws {
        guard documentRoutingOperation == request.id, !isTerminated else {
            throw DocumentSessionError.supersededOperation
        }
        if let caller = request.caller, let ticket = request.ticket {
            try caller.validate(ticket)
            guard
                windows.contains(where: { $0.host === caller.host && $0.configuration.documentWindowContext === caller }
                )
            else { throw DocumentSessionError.ownerUnavailable }
        }
    }

    private static func plainTextType(in types: [UTType]) throws -> UTType {
        if types.contains(.utf8PlainText) { return .utf8PlainText }
        if types.contains(.plainText) { return .plainText }
        throw WindowCoordinatorError.unsupportedDocumentContentTypes
    }

    private func makeNewDocument(
        configuration: WindowGroupConfiguration, services: DocumentWindowServices,
        isPrimary: Bool, request: DocumentRoutingRequest
    ) throws -> WinSwiftUIWindowHost {
        guard let descriptor = configuration.documentScene else { throw WindowCoordinatorError.noDocumentScene }
        try descriptor.validateDocumentType()
        try validate(request)
        guard let makeNew = descriptor.makeNew else { throw WindowCoordinatorError.documentInputRequired }
        let types = descriptor.readableContentTypes()
        try validate(request)
        let type = try Self.plainTextType(in: types)
        return try materializeDocument(
            configuration: configuration, services: services, isPrimary: isPrimary, request: request
        ) { dependencies in
            try makeNew(type, dependencies)
        }
    }

    private func openDocument(
        at selectedURL: URL, configuration: WindowGroupConfiguration,
        services: DocumentWindowServices, request: DocumentRoutingRequest
    ) throws -> WinSwiftUIWindowHost {
        guard selectedURL.isFileURL, !selectedURL.path(percentEncoded: false).utf16.contains(0) else {
            throw DocumentFileServiceError.invalidFileURL
        }
        // Validate before standardization or URL-level deduplication. The live
        // service applies the same rule before IO; a URL authority must not
        // accidentally become an activation of an unrelated local path.
        if let host = selectedURL.host(percentEncoded: true), !host.isEmpty, host.lowercased() != "localhost" {
            throw DocumentFileServiceError.invalidFileURL
        }
        let url = selectedURL.standardizedFileURL
        guard url.pathExtension.lowercased() == "txt" else {
            throw WindowCoordinatorError.unsupportedDocumentExtension(url.pathExtension)
        }
        guard let descriptor = configuration.documentScene else { throw WindowCoordinatorError.noDocumentScene }
        try descriptor.validateDocumentType()
        try validate(request)
        let types = descriptor.readableContentTypes()
        try validate(request)
        let type = try Self.plainTextType(in: types)
        if let existing = existingDocument(at: url, descriptor: descriptor) {
            _ = hooks.activateWindow(existing)
            try validate(request)
            guard !existing.isClosed else { throw WindowCoordinatorError.windowClosedDuringStartup }
            return existing
        }
        let bytes = try services.files.readRegularFile(at: url, maximumBytes: services.maximumReadBytes)
        try validate(request)
        return try materializeDocument(
            configuration: configuration, services: services, isPrimary: false, request: request
        ) { dependencies in
            try descriptor.read(bytes, url, type, dependencies)
        }
    }

    private func existingDocument(at url: URL, descriptor: DocumentSceneDescriptor) -> WinSwiftUIWindowHost? {
        windows.first {
            guard let context = $0.configuration.documentWindowContext else { return false }
            return context.owner.isValid && !$0.host.isClosed && context.descriptor.id == descriptor.id
                && context.session.fileURL?.standardizedFileURL == url
        }?.host
    }

    private func materializeDocument(
        configuration: WindowGroupConfiguration, services: DocumentWindowServices,
        isPrimary: Bool, request: DocumentRoutingRequest,
        makeSession: (DocumentSessionDependencies) throws -> any AnyDocumentSession
    ) throws -> WinSwiftUIWindowHost {
        guard let descriptor = configuration.documentScene else { throw WindowCoordinatorError.noDocumentScene }
        let owner = DocumentOwnerLease()
        var session: (any AnyDocumentSession)?
        var preparedContext: DocumentWindowContext?
        do {
            let manager = services.makeUndoManager()
            try validate(request)
            let prepared = try makeSession(
                DocumentSessionDependencies(owner: owner, files: services.files, undoManager: manager)
            )
            session = prepared
            try validate(request)
            let scope = sceneStorageScopeProvider()
            try validate(request)
            let context = DocumentWindowContext(
                descriptor: descriptor, owner: owner, session: prepared, services: services,
                undoManager: manager, sceneStorageScope: scope
            )
            preparedContext = context
            context.environment = documentEnvironment(for: context, scope: scope)
            var materialized = configuration
            materialized.documentWindowContext = context
            materialized.title = prepared.fileURL?.lastPathComponent ?? configuration.title
            return try openManagedWindow(
                configuration: materialized, presentedValue: nil, isPrimary: isPrimary,
                documentRequest: request
            )
        } catch {
            // Revoke before session/history payload release can run application
            // cleanup. No failed preparation ever becomes a managed window.
            owner.revoke()
            if let host = preparedContext?.host, !host.isClosed {
                host.onWindowClosed = nil
                host.windowWillClose(host.platformWindow)
                if host.platformWindow.nativeHandle != nil { hooks.discardFailedWindow(host) }
            }
            session?.invalidate()
            throw error
        }
    }

    private func documentEnvironment(for context: DocumentWindowContext, scope: String) -> WindowSceneEnvironment {
        WindowSceneEnvironment(
            openWindow: OpenWindowAction(payloadHandler: { [weak self, weak context] payload in
                guard let self, let context, self.isLiveDocumentCaller(context) else { return }
                self.openWindow(payload: payload)
            }),
            dismissWindow: DismissWindowAction(payloadHandler: { [weak self, weak context] payload in
                guard let self, let context, context.owner.isValid,
                    !context.owner.hasCloseCommitReservation, let host = context.host
                else { return }
                if !self.windows.contains(where: { $0.host === host }) {
                    // Dismiss during first construction cancels that pending
                    // admission; it must not wait for a nonexistent HWND.
                    host.windowWillClose(host.platformWindow)
                    return
                }
                self.dismissWindow(payload: payload, from: host)
            }),
            supportsMultipleWindows: true,
            sceneStorageScope: scope,
            openSettings: OpenSettingsAction { [weak self, weak context] in
                guard let self, let context, self.isLiveDocumentCaller(context) else { return }
                self.openSettings()
            },
            newDocument: NewDocumentAction { [weak self, weak context] in
                guard let self, let context, self.isLiveDocumentCaller(context) else { return }
                _ = try? self.newDocument(from: context)
            },
            openDocument: OpenDocumentAction { [weak self, weak context] urls in
                guard let self, let context, self.isLiveDocumentCaller(context) else { return }
                for url in urls {
                    guard self.isLiveDocumentCaller(context) else { return }
                    _ = try? self.openDocument(at: url, from: context)
                }
            },
            saveDocument: SaveDocumentAction { [weak context] url in
                guard let context, context.owner.isValid else { return }
                _ = context.save(to: url)
            }
        )
    }

    private func isLiveDocumentCaller(_ context: DocumentWindowContext) -> Bool {
        context.owner.isValid && !context.owner.hasCloseCommitReservation && !isTerminated
            && windows.contains(where: {
                $0.host === context.host && $0.configuration.documentWindowContext === context
            })
    }

    /// Opens the app's Settings scene once, or shows/restores and requests
    /// activation of its existing window. True reports successful scene
    /// routing; foreground activation remains subject to Windows policy.
    @discardableResult
    func openSettings() -> Bool {
        guard nativeHooks == nil else { return false }
        guard let template = sceneConfigurations.first(where: \.isSettingsWindow) else {
            return false
        }

        if let existing = windows.first(where: { $0.configuration.isSettingsWindow }) {
            _ = hooks.activateWindow(existing.host)
            return true
        }

        do {
            let host = try openManagedWindow(configuration: template, presentedValue: nil, isPrimary: false)
            _ = hooks.activateWindow(host)
            return true
        } catch {
            print("[WinSwiftUI] Failed to open Settings: \(error)")
            return false
        }
    }

    /// Default `dismissWindow` routing: with an id and/or value, closes the
    /// matching windows; with neither, closes the window that owns the
    /// calling scene.
    func dismissWindow(payload: WindowActionPayload, from caller: WinSwiftUIWindowHost?) {
        let targets: [ManagedWindow]
        if payload.id != nil || payload.value != nil {
            targets = windows.filter { window in
                if let id = payload.id, window.configuration.windowID != id {
                    return false
                }
                if let value = payload.value, window.presentedValue != value {
                    return false
                }
                return true
            }
        } else if let caller, let own = windows.first(where: { $0.host === caller }) {
            targets = [own]
        } else {
            targets = []
        }

        for target in targets {
            if let nativeHooks {
                let identity = ObjectIdentifier(target.host)
                if nativeWindowStarts[identity] != nil {
                    nativePendingCloseRequests.insert(identity)
                } else {
                    nativeHooks.requestCloseWindow(target.host)
                }
            } else {
                hooks.requestCloseWindow(target.host)
            }
        }
    }

    /// Runs only under the process's public main-dispatch entry point. Native
    /// acknowledgements suspend this task; they never block actor execution.
    /// Return is after the native thread has stopped and its join completed.
    func runNative() async throws -> Int32 {
        guard let nativeHooks else { throw NativeWindowCoordinatorError.asynchronousOwnerRequired }
        guard !nativeRunStarted else { throw NativeWindowCoordinatorError.alreadyRunning }
        nativeRunStarted = true
        do {
            try await withCheckedThrowingContinuation { continuation in
                nativeStartupWaiter = continuation
                nativeStartupTask = Task { @MainActor in
                    do {
                        try await nativeHooks.startOwner()
                        self.nativeOwnerStarted = true
                        guard !self.isTerminated else { throw WindowCoordinatorError.coordinatorTerminated }
                        _ = try await self.bootPrimaryNativeWindow()
                        self.completeNativeStartup(.success(()))
                    } catch {
                        self.completeNativeStartup(.failure(error))
                    }
                    self.nativeStartupTask = nil
                }
            }
        } catch {
            if nativePrimaryClosedDuringStartup, nativeFatalResult == nil {
                // An ordinary close can win the race with activation or the
                // initial presentation. The terminal close receipt, not a
                // missing first frame, determines normal owner shutdown.
                let stop = await waitForNativeOwnerStop()
                return try await stop.value
            }
            // A failed creation removes its provisional record only after its
            // actual native rollback. Failed rollback intentionally leaves the
            // host owned and does not report a normal, empty-window shutdown.
            if nativeOwnerStarted, windows.isEmpty, nativeWindowStarts.isEmpty {
                startNativeOwnerStop()
                if let nativeStopTask {
                    do { _ = try await nativeStopTask.value } catch let cleanup {
                        throw NativeWindowCoordinatorError.startupAndCleanup(startup: error, cleanup: cleanup)
                    }
                }
            }
            throw error
        }
        let stop = await waitForNativeOwnerStop()
        return try await stop.value
    }

    @discardableResult
    func bootPrimaryNativeWindow() async throws -> WinSwiftUIWindowHost {
        guard nativeOwnerStarted else { throw NativeWindowCoordinatorError.ownerNotStarted }
        if let primary = windows.first(where: \.isPrimary) {
            if let pending = nativeWindowStarts[ObjectIdentifier(primary.host)] {
                return try await pending.value
            }
            return primary.host
        }
        guard let configuration = sceneConfigurations.first(where: { !$0.isSettingsWindow && !$0.isMenuBarExtra })
        else { throw WindowCoordinatorError.noLaunchableWindowScene }
        // The existing native DocumentGroup admission gate is unchanged.
        guard !configuration.isDocumentGroup else { throw WindowCoordinatorError.nativeDocumentActivationUnavailable }
        return try await beginNativeWindow(
            configuration: configuration, presentedValue: nil, isPrimary: true
        ).value
    }

    /// True means the matching scene exists or its creation completed. An
    /// existing scene is not duplicated when Windows declines activation; that
    /// actual Bool is separately exposed by lastNativeActivationResult. Public
    /// Void actions use routeOpenWindow so a synchronous UIA invocation never
    /// waits for a native operation.
    @discardableResult
    func openNativeWindow(payload: WindowActionPayload) async throws -> Bool {
        guard let pending = try beginNativeWindowRequest(payload: payload) else { return false }
        _ = try await pending.value
        return true
    }

    @discardableResult
    func openNativeSettings() async throws -> Bool {
        guard let pending = try beginNativeSettingsRequest() else { return false }
        _ = try await pending.value
        return true
    }

    private func routeOpenWindow(payload: WindowActionPayload) {
        if nativeHooks != nil {
            do { _ = try beginNativeWindowRequest(payload: payload) } catch { recordNativeLifecycleFailure(error) }
        } else {
            _ = openWindow(payload: payload)
        }
    }

    private func routeOpenSettings() {
        if nativeHooks != nil {
            do { _ = try beginNativeSettingsRequest() } catch { recordNativeLifecycleFailure(error) }
        } else {
            _ = openSettings()
        }
    }

    func beginNativeWindowRequest(
        payload: WindowActionPayload
    ) throws -> Task<WinSwiftUIWindowHost, any Error>? {
        guard nativeOwnerStarted else { throw NativeWindowCoordinatorError.ownerNotStarted }
        guard !isTerminated else { throw WindowCoordinatorError.coordinatorTerminated }
        guard payload.id != nil || payload.value != nil else { return nil }
        guard
            let template = sceneConfigurations.first(where: { template in
                guard !template.isSettingsWindow && !template.isMenuBarExtra && !template.isDocumentGroup else {
                    return false
                }
                if let id = payload.id, template.windowID != id { return false }
                if let value = payload.value {
                    guard template.forType == type(of: value.base), template.dataBoundContent != nil else {
                        return false
                    }
                }
                return true
            })
        else { return nil }
        if let value = payload.value,
            let existing = windows.first(where: {
                $0.configuration.windowID == template.windowID && $0.presentedValue == value
            })
        {
            return beginNativeActivation(existing.host)
        }
        return try beginNativeWindow(configuration: template, presentedValue: payload.value, isPrimary: false)
    }

    func beginNativeSettingsRequest() throws -> Task<WinSwiftUIWindowHost, any Error>? {
        guard nativeOwnerStarted else { throw NativeWindowCoordinatorError.ownerNotStarted }
        guard !isTerminated else { throw WindowCoordinatorError.coordinatorTerminated }
        guard let template = sceneConfigurations.first(where: \.isSettingsWindow) else { return nil }
        if let existing = windows.first(where: { $0.configuration.isSettingsWindow }) {
            return beginNativeActivation(existing.host)
        }
        return try beginNativeWindow(configuration: template, presentedValue: nil, isPrimary: false)
    }

    private func beginNativeActivation(_ host: WinSwiftUIWindowHost) -> Task<WinSwiftUIWindowHost, any Error> {
        let startup = nativeWindowStarts[ObjectIdentifier(host)]
        return Task { @MainActor in
            do {
                if let startup { _ = try await startup.value }
                guard self.windows.contains(where: { $0.host === host }), !self.isTerminated,
                    let nativeHooks = self.nativeHooks
                else { throw WindowCoordinatorError.windowClosedDuringStartup }
                // An OS refusal to activate does not duplicate an existing
                // scene. The Bool is the real OS result, not queue admission.
                let activated = try await nativeHooks.activateWindow(host)
                if self.windows.contains(where: { $0.host === host }) {
                    self.nativeActivationResults[ObjectIdentifier(host)] = activated
                }
                return host
            } catch {
                self.recordNativeLifecycleFailure(error)
                throw error
            }
        }
    }

    func lastNativeActivationResult(for host: WinSwiftUIWindowHost) -> Bool? {
        guard windows.contains(where: { $0.host === host }) else { return nil }
        return nativeActivationResults[ObjectIdentifier(host)]
    }

    var failedUnadmittedNativeHostCount: Int { failedNativeUnadmittedHosts.count }

    /// Reserves the actor record before returning to an action's caller. This
    /// preserves Settings/value deduplication and allows an immediately
    /// following dismiss to find a window whose native creation is pending.
    private func beginNativeWindow(
        configuration: WindowGroupConfiguration, presentedValue: AnyHashable?, isPrimary: Bool
    ) throws -> Task<WinSwiftUIWindowHost, any Error> {
        guard let nativeHooks, nativeOwnerStarted else { throw NativeWindowCoordinatorError.ownerNotStarted }
        guard !isTerminated else { throw WindowCoordinatorError.coordinatorTerminated }
        guard !configuration.isDocumentGroup, configuration.documentScene == nil,
            configuration.documentWindowContext == nil
        else { throw WindowCoordinatorError.nativeDocumentActivationUnavailable }
        guard nativeWindowPreparation == nil else { throw NativeWindowCoordinatorError.reentrantWindowPreparation }
        let preparation = UUID()
        nativeWindowPreparation = preparation
        defer {
            if nativeWindowPreparation == preparation { nativeWindowPreparation = nil }
            terminateIfNoWindows()
        }
        let existingHostIdentities = Set(windows.map { ObjectIdentifier($0.host) })
        var configuration = configuration
        let host: WinSwiftUIWindowHost
        var unadmittedHost: WinSwiftUIWindowHost?
        do {
            releaseClosedHosts()
            try validateNativePreparation(preparation)
            if let value = presentedValue, let dataBoundContent = configuration.dataBoundContent {
                configuration.content = dataBoundContent(value)
                try validateNativePreparation(preparation)
            }
            configuration.instantiateWindowContent()
            try validateNativePreparation(preparation)
            let created = try hostFactory(configuration, isPrimary)
            guard !existingHostIdentities.contains(ObjectIdentifier(created)),
                !windows.contains(where: { $0.host === created }), created.documentContext == nil,
                created.onWindowClosed == nil, created.onNativeFailure == nil,
                created.platformWindow.nativeHandle == nil, !created.platformWindow.usesNativeOwner
            else { throw WindowCoordinatorError.documentContextMismatch }
            // Only a newly returned host is ours to roll back. An injected
            // factory returning another managed host never transfers it.
            unadmittedHost = created
            try validateNativePreparation(preparation)
            try created.validateDocumentAdmission(expected: nil)
            try validateNativePreparation(preparation)
            let storageScope = sceneStorageScopeProvider()
            try validateNativePreparation(preparation)
            created.windowEnvironment = WindowSceneEnvironment(
                openWindow: OpenWindowAction(payloadHandler: { [weak self] payload in
                    self?.routeOpenWindow(payload: payload)
                }),
                dismissWindow: DismissWindowAction(payloadHandler: { [weak self, weak created] payload in
                    self?.dismissWindow(payload: payload, from: created)
                }),
                supportsMultipleWindows: true,
                sceneStorageScope: storageScope,
                openSettings: OpenSettingsAction { [weak self] in self?.routeOpenSettings() }
            )
            try validateNativePreparation(preparation)
            try created.validateDocumentAdmission(expected: nil)
            try validateNativePreparation(preparation)
            host = created
        } catch {
            if let unadmittedHost {
                return discardUnadmittedNativeHost(unadmittedHost, admissionError: error, hooks: nativeHooks)
            }
            throw error
        }
        host.onWindowClosed = { [weak self] closedHost in self?.windowDidClose(closedHost) }
        host.onNativeFailure = { [weak self] failedHost, failure in
            self?.nativeOwnerFailed(for: failedHost, failure: failure)
        }
        do {
            try validateNativePreparation(preparation)
            try host.validateDocumentAdmission(expected: nil)
        } catch {
            return discardUnadmittedNativeHost(host, admissionError: error, hooks: nativeHooks)
        }
        windows.append(
            ManagedWindow(
                host: host, configuration: configuration, presentedValue: presentedValue, isPrimary: isPrimary
            ))
        let identity = ObjectIdentifier(host)
        let startup = Task { @MainActor in
            defer {
                self.nativeWindowStarts.removeValue(forKey: identity)
                self.nativeStartupRollbacks.remove(identity)
                self.nativePendingCloseRequests.remove(identity)
                self.terminateIfNoWindows()
            }
            do {
                try await nativeHooks.startWindow(host)
                try host.validateDocumentAdmission(expected: nil)
                guard self.windows.contains(where: { $0.host === host }) else {
                    throw WindowCoordinatorError.windowClosedDuringStartup
                }
                if self.nativePendingCloseRequests.remove(identity) != nil {
                    nativeHooks.requestCloseWindow(host)
                }
                if isPrimary, let configuration = self.liveDiagnosticsConfiguration,
                    self.liveDiagnosticsSession == nil
                {
                    let session = LiveDiagnosticsSession(configuration: configuration, host: host)
                    self.liveDiagnosticsSession = session
                    session.start()
                }
                return host
            } catch {
                if isPrimary, self.nativePrimaryClosedDuringStartup, self.nativeFatalResult == nil,
                    !self.windows.contains(where: { $0.host === host })
                {
                    throw WindowCoordinatorError.windowClosedDuringStartup
                }
                self.recordNativeLifecycleFailure(error)
                if self.windows.contains(where: { $0.host === host }) {
                    self.nativeStartupRollbacks.insert(identity)
                    do {
                        try await nativeHooks.discardFailedWindow(host)
                    } catch let cleanup {
                        self.recordNativeLifecycleFailure(cleanup)
                        // Keep the host and callback: native resources may
                        // still be alive. No synthetic close or normal quit.
                        let failure = NativeWindowCoordinatorError.startupAndCleanup(startup: error, cleanup: cleanup)
                        self.signalFatalNativeFailure(failure)
                        throw failure
                    }
                    host.onWindowClosed = nil
                    host.onNativeFailure = nil
                    self.windows.removeAll { $0.host === host }
                    self.hostsPendingRelease.append(host)
                }
                throw error
            }
        }
        nativeWindowStarts[identity] = startup
        return startup
    }

    private func validateNativePreparation(_ preparation: UUID) throws {
        guard nativeWindowPreparation == preparation, !isTerminated else {
            throw WindowCoordinatorError.coordinatorTerminated
        }
    }

    private func discardUnadmittedNativeHost(
        _ host: WinSwiftUIWindowHost, admissionError: any Error, hooks: WindowCoordinatorNativeHooks
    ) -> Task<WinSwiftUIWindowHost, any Error> {
        let identity = ObjectIdentifier(host)
        let cleanup = Task<WinSwiftUIWindowHost, any Error> { @MainActor in
            defer {
                self.nativeWindowStarts.removeValue(forKey: identity)
                self.terminateIfNoWindows()
            }
            self.recordNativeLifecycleFailure(admissionError)
            do {
                try await hooks.discardFailedWindow(host)
            } catch {
                self.failedNativeUnadmittedHosts[identity] = host
                self.recordNativeLifecycleFailure(error)
                let failure = NativeWindowCoordinatorError.startupAndCleanup(startup: admissionError, cleanup: error)
                self.signalFatalNativeFailure(failure)
                throw failure
            }
            self.hostsPendingRelease.append(host)
            throw admissionError
        }
        nativeWindowStarts[identity] = cleanup
        return cleanup
    }

    private func recordNativeLifecycleFailure(_ error: any Error) {
        let description = String(describing: error)
        nativeLifecycleFailures.append(description)
        print("[WinSwiftUI] Native window operation failed: \(description)")
    }

    private func completeNativeStartup(_ result: Result<Void, any Error>) {
        let waiter = nativeStartupWaiter
        nativeStartupWaiter = nil
        waiter?.resume(with: result)
    }

    /// A fatal native ownership error is not a destruction acknowledgement.
    /// Release the run's waiters with the exact error, keeping the host and any
    /// admitted operation alive until their own terminal result. In particular,
    /// do not cancel a task whose native command may already be executing.
    private func nativeOwnerFailed(for host: WinSwiftUIWindowHost, failure: NativeWindowOwnerFailure) {
        guard windows.contains(where: { $0.host === host }), nativeFatalResult == nil else { return }
        recordNativeLifecycleFailure(failure)
        signalFatalNativeFailure(failure)
    }

    private func signalFatalNativeFailure(_ failure: any Error) {
        guard nativeFatalResult == nil else { return }
        isTerminated = true
        let failed = Task<Int32, any Error> { throw failure }
        nativeFatalResult = failed
        completeNativeStartup(.failure(failure))
        let waiters = nativeStopWaiters
        nativeStopWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: failed) }
    }

    private func startNativeOwnerStop() {
        guard let nativeHooks, nativeOwnerStarted, nativeStopTask == nil,
            windows.isEmpty, nativeWindowStarts.isEmpty, nativeDiagnosticsDrain == nil,
            nativeWindowPreparation == nil, failedNativeUnadmittedHosts.isEmpty
        else { return }
        isTerminated = true
        releaseClosedHosts()
        let stop = Task { @MainActor in try await nativeHooks.stopOwner() }
        nativeStopTask = stop
        let waiters = nativeStopWaiters
        nativeStopWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: stop) }
    }

    private func waitForNativeOwnerStop() async -> Task<Int32, any Error> {
        if let nativeFatalResult { return nativeFatalResult }
        if let nativeStopTask { return nativeStopTask }
        return await withCheckedContinuation { nativeStopWaiters.append($0) }
    }

    @discardableResult
    private func openManagedWindow(
        configuration: WindowGroupConfiguration,
        presentedValue: AnyHashable?,
        isPrimary: Bool,
        documentRequest: DocumentRoutingRequest? = nil
    ) throws -> WinSwiftUIWindowHost {
        let closeBeforeStartup = lastManagedCloseID
        releaseClosedHosts()
        if let documentRequest { try validate(documentRequest) }
        var configuration = configuration
        let expectedContext = configuration.documentWindowContext
        if configuration.isDocumentGroup || configuration.documentScene != nil || expectedContext != nil {
            guard documentServices != nil, hasInjectedDocumentHost,
                documentRequest != nil, expectedContext != nil
            else { throw WindowCoordinatorError.nativeDocumentActivationUnavailable }
        } else {
            configuration.instantiateWindowContent()
        }
        if let documentRequest { try validate(documentRequest) }
        let host = try hostFactory(configuration, isPrimary)
        // A faulty injected factory may return a previously managed host.
        // Reject it without taking that other window's ownership away.
        guard !windows.contains(where: { $0.host === host }) else {
            throw WindowCoordinatorError.documentContextMismatch
        }
        if let expectedContext {
            guard host.documentContext === expectedContext, expectedContext.host === host else {
                // A returned host owned by another context is not ours to
                // destroy, even if it belongs to a different coordinator.
                // materializeDocument revokes only the context we prepared.
                throw WindowCoordinatorError.documentContextMismatch
            }
        } else if host.documentContext != nil {
            throw WindowCoordinatorError.documentContextMismatch
        }
        do {
            if let documentRequest { try validate(documentRequest) }
            try host.validateDocumentAdmission(expected: expectedContext)
            if expectedContext == nil {
                host.windowEnvironment = WindowSceneEnvironment(
                    openWindow: OpenWindowAction(payloadHandler: { [weak self] payload in
                        self?.openWindow(payload: payload)
                    }),
                    dismissWindow: DismissWindowAction(payloadHandler: { [weak self, weak host] payload in
                        self?.dismissWindow(payload: payload, from: host)
                    }),
                    supportsMultipleWindows: true,
                    sceneStorageScope: sceneStorageScopeProvider(),
                    openSettings: OpenSettingsAction { [weak self] in
                        self?.openSettings()
                    }
                )
            }
            if let documentRequest { try validate(documentRequest) }
            try host.validateDocumentAdmission(expected: expectedContext)
            host.onWindowClosed = { [weak self] closedHost in
                self?.windowDidClose(closedHost)
            }
            windows.append(
                ManagedWindow(
                    host: host, configuration: configuration,
                    presentedValue: presentedValue, isPrimary: isPrimary
                )
            )
            try hooks.startWindow(host)
            if let documentRequest { try validate(documentRequest) }
            try host.validateDocumentAdmission(expected: expectedContext)
            guard windows.contains(where: { $0.host === host }) else {
                throw WindowCoordinatorError.windowClosedDuringStartup
            }
        } catch {
            // A failed creation must not leave a registered phantom window
            // that consumes the Settings singleton or prevents app exit.
            // Tear down a partially attached renderer without applying the
            // normal last-window quit policy, so a later open can retry.
            expectedContext?.owner.revoke()
            host.onWindowClosed = nil
            windows.removeAll { $0.host === host }
            host.windowWillClose(host.platformWindow)
            if host.platformWindow.nativeHandle != nil {
                hooks.discardFailedWindow(host)
            }
            // A provisional child can briefly keep windows nonempty while
            // its last admitted caller closes inside startWindow. Removing
            // that failed child must finish the real last-window close. An
            // initial startup failure with no close remains retryable.
            if lastManagedCloseID != closeBeforeStartup {
                terminateIfNoWindows()
            }
            throw error
        }

        // After `startWindow`: the session's first frame request needs a
        // window that has been created and has a presenter attached, which is
        // what `Win32Application.start` completes.
        if expectedContext == nil, isPrimary, let liveDiagnosticsConfiguration, liveDiagnosticsSession == nil {
            let session = LiveDiagnosticsSession(configuration: liveDiagnosticsConfiguration, host: host)
            liveDiagnosticsSession = session
            session.start()
        }

        return host
    }

    private func windowDidClose(_ host: WinSwiftUIWindowHost) {
        guard nativeHooks != nil else {
            legacyWindowDidClose(host)
            return
        }
        let previousWindows = windows
        guard let managed = previousWindows.first(where: { $0.host === host }) else { return }
        // Keep removed records alive until their replacement bookkeeping is
        // fully published, including captures owned only by the configuration.
        defer { withExtendedLifetime(previousWindows) {} }
        let identity = ObjectIdentifier(host)
        if managed.isPrimary, nativeWindowStarts[identity] != nil,
            !nativeStartupRollbacks.contains(identity)
        {
            nativePrimaryClosedDuringStartup = true
        }
        lastManagedCloseID = UUID()
        windows.removeAll { $0.host === host }
        nativeActivationResults.removeValue(forKey: ObjectIdentifier(host))
        // Releasing a previous host can destroy authored captures that call a
        // retained window action. Publish removal and reserve final admission
        // before diagnostics or any such release is allowed to run.
        if windows.isEmpty { isTerminated = true }
        if let finish = liveDiagnosticsSession?.finishAfterHostClosed(host) {
            nativeDiagnosticsDrain = Task { @MainActor in
                await finish.value
                self.nativeDiagnosticsDrain = nil
                self.terminateIfNoWindows()
            }
        }
        releaseClosedHosts()
        // Native callbacks arrive after the final dispatch acknowledgement;
        // deferring actor release also lets diagnostics take its final snapshot.
        hostsPendingRelease.append(host)
        Task { @MainActor [weak self] in
            self?.releaseClosedHosts()
        }

        terminateIfNoWindows()
    }

    private func legacyWindowDidClose(_ host: WinSwiftUIWindowHost) {
        guard windows.contains(where: { $0.host === host }) else { return }
        lastManagedCloseID = UUID()
        _ = liveDiagnosticsSession?.finishAfterHostClosed(host)
        // Preserve the synchronous host contract: an earlier host's final
        // release may open a replacement while this close is on the stack.
        // Recheck the actual remaining windows afterward, never a saved quit
        // decision. The shared release queue is still safe to reenter.
        releaseClosedHosts()
        windows.removeAll { $0.host === host }
        hostsPendingRelease.append(host)
        Task { @MainActor [weak self] in
            self?.releaseClosedHosts()
        }
        terminateIfNoWindows()
    }

    private func terminateIfNoWindows() {
        guard windows.isEmpty else { return }
        if nativeHooks != nil {
            // Reserve final shutdown immediately. Outstanding work delays the
            // owner stop; it does not reopen admission to a stale environment.
            isTerminated = true
            guard nativeOwnerStarted, nativeWindowStarts.isEmpty, nativeDiagnosticsDrain == nil,
                nativeWindowPreparation == nil, failedNativeUnadmittedHosts.isEmpty
            else { return }
            startNativeOwnerStop()
            return
        }
        if !isTerminated {
            isTerminated = true
            hooks.terminateMessageLoop()
        }
    }

    private func releaseClosedHosts() {
        // Take the complete batch before ARC can call authored deinitializers.
        // A reentrant open/close sees a new empty queue, never an Array mutation
        // that is still borrowing this property for exclusive access.
        let pending = hostsPendingRelease
        hostsPendingRelease = []
        withExtendedLifetime(pending) {}
    }
}
