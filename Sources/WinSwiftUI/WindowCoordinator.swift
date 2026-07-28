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
}

/// Hosts every live `WindowGroup` window of a running `WinSwiftUI.App`.
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

    /// Scene templates declared by the app body. Today the app model yields a
    /// single configuration; the coordinator accepts several so id- and
    /// value-based routing works the moment multi-scene app bodies exist.
    private let sceneConfigurations: [WindowGroupConfiguration]
    private let hooks: WindowCoordinatorHooks
    private let hostFactory: @MainActor (WindowGroupConfiguration, Bool) -> WinSwiftUIWindowHost
    private let sceneStorageScopeProvider: @MainActor () -> String

    private(set) var windows: [ManagedWindow] = []
    private var isTerminated = false

    var windowCount: Int {
        windows.count
    }

    init(
        sceneConfigurations: [WindowGroupConfiguration],
        // Backend-neutral default (portable CPU reference backend); `App.main()`
        // always passes the app's `renderBackendFactory()` explicitly, so this
        // default only serves direct coordinator users such as tests.
        renderBackendFactory: RenderBackendFactory = CPURenderBackendFactory(),
        hooks: WindowCoordinatorHooks = .win32,
        hostFactory: (@MainActor (WindowGroupConfiguration, Bool) -> WinSwiftUIWindowHost)? = nil,
        sceneStorageScopeProvider: (@MainActor () -> String)? = nil
    ) {
        precondition(!sceneConfigurations.isEmpty, "WinSwiftUIWindowCoordinator requires at least one scene.")
        self.sceneConfigurations = sceneConfigurations
        self.hooks = hooks
        self.hostFactory =
            hostFactory
            ?? { configuration, isPrimary in
                WinSwiftUIWindowHost(
                    configuration: configuration,
                    renderer: renderBackendFactory.makeRenderBackend(),
                    batchRenderer: renderBackendFactory.makeBatchRenderBackend(),
                    // Only the primary window writes the startup probe;
                    // secondary windows must not overwrite it on open.
                    startupProbeConfiguration: isPrimary ? .fromEnvironment() : nil
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

        return try openManagedWindow(
            configuration: sceneConfigurations[0],
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
            windows.contains(where: { $0.configuration.windowID == template.windowID && $0.presentedValue == value })
        {
            // SwiftUI re-presents the existing window for an already-open
            // value rather than opening a duplicate.
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
        let host = hostFactory(configuration, isPrimary)
        host.windowEnvironment = WindowSceneEnvironment(
            openWindow: OpenWindowAction(payloadHandler: { [weak self] payload in
                self?.openWindow(payload: payload)
            }),
            dismissWindow: DismissWindowAction(payloadHandler: { [weak self, weak host] payload in
                self?.dismissWindow(payload: payload, from: host)
            }),
            supportsMultipleWindows: true,
            sceneStorageScope: sceneStorageScopeProvider()
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
        try hooks.startWindow(host)
        return host
    }

    private func windowDidClose(_ host: WinSwiftUIWindowHost) {
        windows.removeAll { $0.host === host }
        if windows.isEmpty, !isTerminated {
            isTerminated = true
            hooks.terminateMessageLoop()
        }
    }
}
