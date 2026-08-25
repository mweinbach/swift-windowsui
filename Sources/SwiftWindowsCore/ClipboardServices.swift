/// A platform-neutral source of plain-text clipboard data.
///
/// Window-system implementations own the native clipboard representation;
/// callers exchange ordinary Swift strings without depending on Win32,
/// AppKit, or another platform's pasteboard API. Clipboard access is confined
/// to the main actor because UI editing and clipboard ownership are
/// main-thread services on the supported desktop platforms.
@MainActor
public protocol ClipboardTextStore: AnyObject {
    /// Whether the clipboard currently exposes a plain-text representation.
    ///
    /// An available empty string still counts as a text representation.
    var hasText: Bool { get }

    /// Replaces the clipboard's current payload with `text`.
    func copyString(_ text: String)

    /// Returns the clipboard's current plain-text payload, when available.
    func pasteString() -> String?
}
