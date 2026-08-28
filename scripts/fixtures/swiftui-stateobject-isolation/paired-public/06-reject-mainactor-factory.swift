#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Rejection case: a plain thunk formed in a nonisolated function cannot
// synchronously call this explicitly MainActor-only factory.
@MainActor
private func makeActorOnlyModel() -> PureModel {
    PureModel(seed: 6)
}

func rejectActorOnlyFactory() -> StateObject<PureModel> {
    StateObject(wrappedValue: makeActorOnlyModel())
}
