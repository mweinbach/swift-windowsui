import WinSDK

/// Passive metadata from an existing native timer-off publication. This is
/// not an idle-interval sample, a message-producer identity or an ownership capability.
package enum Win32NativeSmokeGUIThreadState {
    /// Zero means the query failed. Successful values use bit 7 for success,
    /// bits 5...6 for no caret / recorded HWND / different reported HWND,
    /// and the low five bits for the documented GUITHREADINFO flags.
    /// GUI_CARETBLINKING reports visibility now, not whether a timer is enabled.
    package static func encode(
        querySucceeded: Bool, hasCaret: Bool, matchesRecordedWindow: Bool, flags: UInt32
    ) -> UInt64 {
        guard querySucceeded else { return 0 }
        let association: UInt64 = hasCaret ? (matchesRecordedWindow ? 1 : 2) : 0
        return 0x80 + (association << 5) + UInt64(flags & 0x1F)
    }

    /// Called only on the executing native owner with its live recorded HWND.
    /// Never pass zero to GetGUIThreadInfo: it selects the foreground thread.
    /// A missing current ID leaves the metadata absent; a failed query yields zero.
    /// Returned handles are compared locally and never queried, exposed or retained.
    static func sample(recordedWindow: HWND) -> UInt64? {
        let nativeThreadID = GetCurrentThreadId()
        guard nativeThreadID != 0 else { return nil }
        var information = GUITHREADINFO()
        information.cbSize = DWORD(MemoryLayout<GUITHREADINFO>.size)
        guard GetGUIThreadInfo(nativeThreadID, &information) else { return 0 }
        return encode(
            querySucceeded: true, hasCaret: information.hwndCaret != nil,
            matchesRecordedWindow: information.hwndCaret == recordedWindow, flags: information.flags)
    }
}
