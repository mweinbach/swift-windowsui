import Dispatch
import Foundation
import WinSDK

/// A failure the application can report without accessing a window host.
///
/// ``App/handleFailure(_:)`` runs on the main actor. Presenter exhaustion is
/// delivered at most once per window lifetime, after presentation work and its
/// actor reply have settled. The window remains owned and closable; the event
/// is not a destruction receipt or proof that renderer cleanup succeeded.
///
/// Startup delivery requires a successful native-owner stop and thread join.
/// Failures that leave ownership or cleanup unproven retain the immediate
/// process-fatal policy without calling app code. Synchronous custom platform
/// startup failures also retain their existing print/return behavior.
public struct AppFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case startup
        case presenterUnavailable
    }

    /// A copied identity, never an HWND, runtime, model or window action.
    public struct Window: Equatable, Sendable {
        public let id: UUID
        public let sceneID: String?
        public let title: String
    }

    public let kind: Kind
    public let window: Window?
    public let message: String

    /// Shows an ownerless Windows error dialog without using the renderer.
    /// The main actor and native owner keep running while it is visible.
    /// This suspends until dismissal (or a native presentation failure); it
    /// neither retries graphics work nor closes a window. A startup caller
    /// then follows the existing failure exit status.
    public func presentNativeAlert() async {
        let title = window?.title ?? "Application could not start"
        let advice: String
        switch kind {
        case .startup:
            advice = "The application could not start and will exit."
        case .presenterUnavailable:
            advice = "This window cannot display its contents. You can close it and restart the application."
        }
        let text = "\(advice)\n\n\(message)"
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // No HWND crosses executors. In particular, this dialog must
                // never acquire ownership of a possibly failed native window.
                let caption = Array(title.utf16) + [0]
                let body = Array(text.utf16) + [0]
                let result = body.withUnsafeBufferPointer { body in
                    caption.withUnsafeBufferPointer { caption in
                        MessageBoxW(nil, body.baseAddress, caption.baseAddress, UINT(MB_OK | MB_ICONERROR))
                    }
                }
                if result == 0 {
                    print("[WinSwiftUI] Native failure alert could not be shown: \(GetLastError()).")
                }
                continuation.resume()
            }
        }
    }
}
