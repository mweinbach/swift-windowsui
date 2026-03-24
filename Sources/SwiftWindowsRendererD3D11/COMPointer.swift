// Gap 7: COM RAII wrapper — prevents leak/double-release bugs on COM objects

import WinSDK

@MainActor
final class COMPointer<T> {
    private(set) var pointer: UnsafeMutablePointer<T>?

    // Mirror of `pointer` stored as a Sendable integer so deinit can release
    // the COM object without accessing the @MainActor-isolated property.
    private nonisolated(unsafe) var rawBits: UInt = 0

    init(_ pointer: UnsafeMutablePointer<T>? = nil) {
        self.pointer = pointer
        self.rawBits = pointer.flatMap { UInt(bitPattern: $0) } ?? 0
    }

    var raw: UnsafeMutableRawPointer? {
        pointer.map { UnsafeMutableRawPointer($0) }
    }

    func set(_ newPointer: UnsafeMutablePointer<T>?) {
        if pointer != nil {
            release()
        }
        pointer = newPointer
        rawBits = newPointer.flatMap { UInt(bitPattern: $0) } ?? 0
    }

    func take() -> UnsafeMutablePointer<T>? {
        let p = pointer
        pointer = nil
        rawBits = 0
        return p
    }

    func release() {
        guard let p = pointer else { return }
        let unknown = UnsafeMutableRawPointer(p).assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        pointer = nil
        rawBits = 0
    }

    deinit {
        // Release using the Sendable rawBits mirror. Safe because:
        // 1. COMPointer is only used on the main actor
        // 2. rawBits is always kept in sync with pointer
        // 3. deinit runs when the last reference drops (deterministic)
        guard rawBits != 0 else { return }
        let raw = UnsafeMutableRawPointer(bitPattern: rawBits)!
        let unknown = raw.assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    }
}
