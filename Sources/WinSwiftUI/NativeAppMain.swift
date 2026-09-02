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
        liveDiagnostics: LiveDiagnosticsConfiguration?,
        nativeStartupPhaseProbe: NativeStartupPhaseProbe? = nil
    ) {
        if let platform = platformHostFactory as? any Win32NativePlatformHostFactory,
            let presentation = renderBackendFactory.makeNativePresentationFactory()
        {
            let acquisitionSession: NativeDisplayAcquisitionSession?
            do {
                acquisitionSession = try NativeDisplayAcquisitionSession.makeIfRequested(
                    arguments: CommandLine.arguments)
            } catch {
                // Invalid opt-in configuration does not change application
                // startup or its exit policy, and cannot publish a journal.
                print("Native display journal is unavailable: \(error)")
                acquisitionSession = nil
            }
            let pump = platform.makeNativePump()
            let coordinator = WinSwiftUIWindowCoordinator(
                sceneConfigurations: sceneConfigurations,
                renderBackendFactory: renderBackendFactory,
                backendResolution: backendResolution,
                platformHostFactory: platformHostFactory,
                nativeHooks: .win32(pump),
                nativePresentationFactory: presentation,
                liveDiagnostics: liveDiagnostics,
                nativeDisplayAcquisition: acquisitionSession?.recorder,
                nativeStartupPhaseProbe: nativeStartupPhaseProbe
            )
            Task { @MainActor in
                nativeStartupPhaseProbe?.record(.nativeTaskEntered)
                let exitCode: Int32
                do {
                    // Normal completion is after every window's destruction
                    // acknowledgement and the native thread's actual join.
                    exitCode = try await coordinator.runNative()
                    nativeStartupPhaseProbe?.record(.nativeRunReturned)
                    if let issue = acquisitionSession?.retire(successfullyJoined: true) { print(issue) }
                    // This records return from the retirement/report step,
                    // including its failure report, never publication success.
                    if acquisitionSession != nil { nativeStartupPhaseProbe?.record(.retirementReturned) }
                } catch {
                    // Some failure paths still own native work. Do not sample,
                    // serialize, retry shutdown, or write from this catch.
                    acquisitionSession?.retire(successfullyJoined: false)
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
