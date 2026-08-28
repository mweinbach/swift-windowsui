#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Record the platform outcome. A model-initializer isolation error caused
// by ObservableObject conformance cannot qualify the StateObject boundary.
func makeOrdinaryModelWrapper() -> StateObject<OrdinaryProbeModel> {
    StateObject(wrappedValue: OrdinaryProbeModel(seed: 7))
}
