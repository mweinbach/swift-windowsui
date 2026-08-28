#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission control for the explicitly actor-only factory below.
@MainActor
private func makeActorOnlyModel() -> PureModel {
    PureModel(seed: 6)
}

@MainActor
func constructFromActorOnlyFactory() -> StateObject<PureModel> {
    StateObject(wrappedValue: makeActorOnlyModel())
}
