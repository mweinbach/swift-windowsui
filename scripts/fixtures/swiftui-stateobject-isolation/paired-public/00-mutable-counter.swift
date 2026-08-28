#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Deliberately non-Sendable and nonisolated in the required client configuration.
// It has no UI protocol conformance, actor annotation, or synchronization.
final class ProbeMutableCounter {
    var value = 0

    func advance() -> Int {
        value += 1
        return value
    }
}
