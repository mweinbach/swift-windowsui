#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission control for the wrapper's Sendable behavior.
// The wrapper is only passed as a value; no factory or body is evaluated.
private func acceptSendable<Value: Sendable>(_ value: Value) {}

func requireWrapperSendability(_ wrapper: StateObject<PureModel>) {
    acceptSendable(wrapper)
}
