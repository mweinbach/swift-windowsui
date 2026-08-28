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
/// scene-storage scope. Everything stays on the main actor, matching the
/// rest of the UI stack.
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
    private let hostFactory: @MainActor (WindowGroupConfiguration, Bool) throws -> WinSwiftUIWindowHost
    private let sceneStorageScopeProvider: @MainActor () -> String
    private let documentServices: DocumentWindowServices?
    private let hasInjectedDocumentHost: Bool
    private var documentRoutingOperation: UUID?

    private(set) var windows: [ManagedWindow] = []
    private var isTerminated = false
    private var lastManagedCloseID: UUID?

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
        hostFactory: (@MainActor (WindowGroupConfiguration, Bool) throws -> WinSwiftUIWindowHost)? = nil,
        sceneStorageScopeProvider: (@MainActor () -> String)? = nil,
        liveDiagnostics: LiveDiagnosticsConfiguration? = nil,
        documentServices: DocumentWindowServices? = nil
    ) {
        self.sceneConfigurations = sceneConfigurations
        self.documentServices = documentServices
        self.hasInjectedDocumentHost = hooks != nil && hostFactory != nil
        self.hooks = hooks ?? .platform(platformHostFactory)
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

                return WinSwiftUIWindowHost(
                    configuration: configuration,
                    platformWindow: win32Window,
                    renderer: renderBackendFactory.makeRenderBackend(),
                    batchRenderer: renderBackendFactory.makeBatchRenderBackend(),
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
        try bootPrimaryWindow()
        return try hooks.runMessageLoop()
    }

    /// Creates the primary host/window and starts it without entering the
    /// message loop. Internal so headless tests can drive the coordinator
    /// without a real run loop.
    @discardableResult
    func bootPrimaryWindow() throws -> WinSwiftUIWindowHost {
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
            hooks.requestCloseWindow(target.host)
        }
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
        guard windows.contains(where: { $0.host === host }) else { return }
        lastManagedCloseID = UUID()
        releaseClosedHosts()
        windows.removeAll { $0.host === host }
        // Outlive the wndproc frame this is running inside. The message loop
        // does not drain the main-actor executor, so the deferred task is a
        // best-effort drain and not the only one: the next close or open
        // releases it regardless.
        hostsPendingRelease.append(host)
        Task { @MainActor [weak self] in
            self?.releaseClosedHosts()
        }

        terminateIfNoWindows()
    }

    private func terminateIfNoWindows() {
        if windows.isEmpty, !isTerminated {
            isTerminated = true
            hooks.terminateMessageLoop()
        }
    }

    private func releaseClosedHosts() {
        hostsPendingRelease.removeAll()
    }
}
