#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Rejection control for the compiler's transfer checks, without StateObject.
// Compile only; never invoke. It is not evidence about the wrapper by itself.
func directCounterTransferControl() -> Task<Void, Never> {
    Task.detached {
        let counter = ProbeMutableCounter()
        let alias = counter
        let reader = Task { @MainActor [alias] in
            _ = alias.advance()
        }
        _ = counter.advance()
        _ = reader
    }
}
