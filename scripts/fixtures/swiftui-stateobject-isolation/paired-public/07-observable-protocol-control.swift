#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Confound control without any StateObject use. If this model construction
// rejects, retain that protocol-inference diagnostic separately.
func makeOrdinaryModelDirectly() -> OrdinaryProbeModel {
    OrdinaryProbeModel(seed: 7)
}
