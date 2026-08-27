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

enum WindowCoordinatorError: Error, Equatable, CustomStringConvertible {
    case noLaunchableWindowScene

    var description: String {
        switch self {
        case .noLaunchableWindowScene:
            return
                "The app declares no launchable window scene. Settings opens on demand; MenuBarExtra hosting is unsupported."
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

    private(set) var windows: [ManagedWindow] = []
    private var isTerminated = false

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
        liveDiagnostics: LiveDiagnosticsConfiguration? = nil
    ) {
        self.sceneConfigurations = sceneConfigurations
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
                guard !template.isSettingsWindow && !template.isMenuBarExtra else {
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
        isPrimary: Bool
    ) throws -> WinSwiftUIWindowHost {
        releaseClosedHosts()
        var configuration = configuration
        configuration.instantiateWindowContent()
        let host = try hostFactory(configuration, isPrimary)
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
        host.onWindowClosed = { [weak self] closedHost in
            self?.windowDidClose(closedHost)
        }
        windows.append(
            ManagedWindow(
                host: host,
                configuration: configuration,
                presentedValue: presentedValue,
                isPrimary: isPrimary
            )
        )
        do {
            try hooks.startWindow(host)
        } catch {
            // A failed creation must not leave a registered phantom window
            // that consumes the Settings singleton or prevents app exit.
            // Tear down a partially attached renderer without applying the
            // normal last-window quit policy, so a later open can retry.
            host.onWindowClosed = nil
            windows.removeAll { $0.host === host }
            host.windowWillClose(host.platformWindow)
            if host.platformWindow.nativeHandle != nil {
                hooks.discardFailedWindow(host)
            }
            throw error
        }

        // After `startWindow`: the session's first frame request needs a
        // window that has been created and has a presenter attached, which is
        // what `Win32Application.start` completes.
        if isPrimary, let liveDiagnosticsConfiguration, liveDiagnosticsSession == nil {
            let session = LiveDiagnosticsSession(configuration: liveDiagnosticsConfiguration, host: host)
            liveDiagnosticsSession = session
            session.start()
        }

        return host
    }

    private func windowDidClose(_ host: WinSwiftUIWindowHost) {
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

        if windows.isEmpty, !isTerminated {
            isTerminated = true
            hooks.terminateMessageLoop()
        }
    }

    private func releaseClosedHosts() {
        hostsPendingRelease.removeAll()
    }
}
