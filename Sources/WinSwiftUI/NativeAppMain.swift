import Dispatch
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import WinSDK

/// The native-owner path leaves the entry thread in the supported main
/// dispatch loop. The actor task owns all application state; it suspends for
/// native replies while the HWND thread continues its ordinary message loop.
@MainActor
enum WinSwiftUIAppMain {
    static func run<Application: App>(
        application: Application,
        sceneConfigurations: [WindowGroupConfiguration],
        renderBackendFactory: any RenderBackendFactory,
        backendResolution: RenderBackendResolution,
        platformHostFactory: any PlatformHostFactory,
        liveDiagnostics: LiveDiagnosticsConfiguration?
    ) {
        if let platform = platformHostFactory as? any Win32NativePlatformHostFactory,
            let presentation = renderBackendFactory.makeNativePresentationFactory()
        {
            let pump = platform.makeNativePump()
            let coordinator = WinSwiftUIWindowCoordinator(
                sceneConfigurations: sceneConfigurations,
                renderBackendFactory: renderBackendFactory,
                backendResolution: backendResolution,
                platformHostFactory: platformHostFactory,
                nativeHooks: .win32(pump),
                nativePresentationFactory: presentation,
                liveDiagnostics: liveDiagnostics
            )
            Task { @MainActor in
                let exitCode: Int32
                do {
                    // Normal completion is after every window's destruction
                    // acknowledgement and the native thread's actual join.
                    exitCode = try await coordinator.runNative()
                } catch {
                    // Failed/quiesced resources are never relabeled closed.
                    // This is a fatal startup/owner error, not graceful exit.
                    print("Failed to run WinSwiftUI native owner: \(error)")
                    exitCode = 1
                }
                withExtendedLifetime(application) {}
                withExtendedLifetime(coordinator) {}
                ExitProcess(DWORD(bitPattern: exitCode))
            }
            dispatchMain()
        }

        // Existing custom factories and direct/headless embedders retain the
        // synchronous protocol they implement. They have not opted into the
        // native-owner scheduling and presentation contract.
        let coordinator = WinSwiftUIWindowCoordinator(
            sceneConfigurations: sceneConfigurations,
            renderBackendFactory: renderBackendFactory,
            backendResolution: backendResolution,
            platformHostFactory: platformHostFactory,
            liveDiagnostics: liveDiagnostics
        )
        do { _ = try coordinator.run() } catch { print("Failed to start WinSwiftUI app: \(error)") }
        withExtendedLifetime(application) {}
    }
}
