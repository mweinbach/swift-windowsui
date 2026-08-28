#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Rejection case. Compile only; never invoke scheduleReader().
actor CounterCaptureActor {
    private let counter = ProbeMutableCounter()

    func scheduleReader() -> Task<Void, Never> {
        let alias = counter
        let wrapper = StateObject(wrappedValue: PureModel(seed: alias.advance()))
        let reader = Task { @MainActor [wrapper] in
            _ = wrapper.wrappedValue
        }
        // The actor keeps and reuses its alias after scheduling MainActor access.
        // No direct foreign-actor property access is used as a substitute error.
        _ = alias.advance()
        return reader
    }
}
