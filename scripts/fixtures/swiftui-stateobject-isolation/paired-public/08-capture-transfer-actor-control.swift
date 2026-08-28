#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission control for the actor syntax and model construction.
// The scheduled reader does not retain the actor's counter.
actor CounterCaptureControlActor {
    private let counter = ProbeMutableCounter()

    func scheduleReader() -> Task<Void, Never> {
        let alias = counter
        let seed = alias.advance()
        let wrapper = StateObject(wrappedValue: PureModel(seed: seed))
        let reader = Task { @MainActor [wrapper] in
            _ = wrapper.wrappedValue
        }
        _ = alias.advance()
        return reader
    }
}
