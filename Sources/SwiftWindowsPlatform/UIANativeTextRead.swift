import CUIAInterop
import Synchronization

/// Only the bridge owns actor ranges. Native handles retain a callback box
/// whose mailbox contains numbers, never this store or its values.
@MainActor
final class UIANativeTextReadStore {
    private var ranges: [UInt64: UIATextRange] = [:]
    private var isClosed = false

    var count: Int { ranges.count }

    func register(_ range: UIATextRange, ticket: UInt64) -> Bool {
        guard !isClosed, ticket != 0, ranges[ticket] == nil else { return false }
        ranges[ticket] = range
        return true
    }

    func range(for ticket: UInt64) -> UIATextRange? {
        guard !isClosed else { return nil }
        return ranges[ticket]
    }

    func retire(_ tickets: [UInt64]) {
        for ticket in tickets { ranges.removeValue(forKey: ticket) }
    }

    func close() {
        isClosed = true
        ranges.removeAll()
    }
}

/// Final native Release may enqueue on any thread, even after quiescence.
/// Scheduling and consuming a batch use the same lock so a racing enqueue
/// either joins that batch or claims a new drain. No actor values enter it.
final class UIANativeTextReadRetirements: Sendable {
    private struct State: Sendable {
        var tickets: [UInt64] = []
        var scheduled = false
        var closed = false
    }

    private let state = Mutex(State())

    func enqueue(_ ticket: UInt64) -> Bool {
        state.withLock { state in
            guard !state.closed, ticket != 0 else { return false }
            state.tickets.append(ticket)
            guard !state.scheduled else { return false }
            state.scheduled = true
            return true
        }
    }

    func take() -> [UInt64] {
        state.withLock { state in
            let tickets = state.tickets
            state.tickets = []
            state.scheduled = false
            return tickets
        }
    }

    func close() {
        state.withLock { state in
            state.closed = true
            state.tickets = []
            state.scheduled = false
        }
    }
}

enum UIANativeTextReadBuffer {
    /// Count exact UTF16 units, not Characters. Testable without allocating a
    /// huge String; the actual allocation still reports its own failure.
    static func checkedLength(_ utf16Count: Int) -> Int32? {
        guard utf16Count >= 0, utf16Count <= Int(Int32.max) else { return nil }
        return Int32(utf16Count)
    }

    static func copy(_ value: String, call: OpaquePointer?) -> UnsafeMutablePointer<UInt16>? {
        guard let length = checkedLength(value.utf16.count) else {
            SWU_UIACallFail(call, Int32(bitPattern: 0x8007_000E))
            return nil
        }
        var units = Array(value.utf16)
        if units.isEmpty { units = [0] }
        let result = units.withUnsafeBufferPointer { SWU_UIACreateBSTR($0.baseAddress, length) }
        if result == nil { SWU_UIACallFail(call, Int32(bitPattern: 0x8007_000E)) }
        return result
    }
}

/// Separate optional callback ABI. It shares the explicit-call table's box;
/// there is no additional context retain or final-release hook.
enum UIANativeTextReadCallbacks {
    static func make() -> SWUUIATextReadCallbacks {
        var callbacks = SWUUIATextReadCallbacks()
        callbacks.acquire = { call, element, ticket in acquire(call, element, ticket) }
        callbacks.copyText = { call, ticket, maximum in copyText(call, ticket, maximum) }
        callbacks.retire = { raw, ticket in
            guard let raw else { return }
            Unmanaged<UIANativeCallbackContext>.fromOpaque(raw).takeUnretainedValue().retireTextRead(ticket)
        }
        return callbacks
    }

    static func acquire(_ call: OpaquePointer?, _ element: UInt64, _ ticket: UInt64) -> Int32 {
        guard let reply = UIANativeRequestDispatch.perform(call, .acquireTextRead(element: element, ticket: ticket))
        else {
            if SWU_UIACallStatus(call) >= 0 { UIANativeRequestDispatch.unexpectedReply(call) }
            return SWU_UIACallStatus(call)
        }
        guard case .integer(let registered) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return SWU_UIACallStatus(call)
        }
        return registered == 1 ? 0 : UIANativeHRESULT.elementNotAvailable
    }

    static func copyText(
        _ call: OpaquePointer?, _ ticket: UInt64, _ maximumUTF16Length: Int32
    ) -> UnsafeMutablePointer<UInt16>? {
        // Validate before the bridge's generic thrown-error handler. The Core
        // helper policy is selected explicitly here, not claimed as UIA parity.
        guard maximumUTF16Length >= -1 else {
            SWU_UIACallFail(call, Int32(bitPattern: 0x8007_0057))
            return nil
        }
        guard
            let reply = UIANativeRequestDispatch.perform(
                call, .readTextRead(ticket: ticket, maximumUTF16Length: maximumUTF16Length))
        else { return nil }
        guard case .string(let value) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return nil
        }
        guard let value else {
            SWU_UIACallFail(call, UIANativeHRESULT.elementNotAvailable)
            return nil
        }
        return UIANativeTextReadBuffer.copy(value, call: call)
    }
}
