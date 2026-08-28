#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Rejection case. Compile only; never invoke this function.
// Constructing the counter inside the detached task avoids an earlier task-capture
// transfer. The counter must remain inside the deferred expression below.
func taskCaptureTransfer() -> Task<Void, Never> {
    Task.detached {
        let counter = ProbeMutableCounter()
        let alias = counter
        let wrapper = StateObject(wrappedValue: PureModel(seed: alias.advance()))
        let reader = Task { @MainActor [wrapper] in
            _ = wrapper.wrappedValue
        }
        // No await or other ordering edge separates the scheduled reader from
        // this write to the same counter retained by the deferred factory.
        _ = counter.advance()
        _ = reader
    }
}
