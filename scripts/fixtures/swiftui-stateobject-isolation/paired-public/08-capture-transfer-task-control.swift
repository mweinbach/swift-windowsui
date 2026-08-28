#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission control for the task syntax and model construction.
// The thunk captures an immutable Int, not the mutable counter.
func taskCaptureTransferControl() -> Task<Void, Never> {
    Task.detached {
        let counter = ProbeMutableCounter()
        let alias = counter
        let seed = alias.advance()
        let wrapper = StateObject(wrappedValue: PureModel(seed: seed))
        let reader = Task { @MainActor [wrapper] in
            _ = wrapper.wrappedValue
        }
        _ = counter.advance()
        _ = reader
    }
}
