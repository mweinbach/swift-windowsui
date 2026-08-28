#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Paired public-source admission case. No caller evaluates body.
@MainActor
struct ExplicitInitializerOwner: View {
    @StateObject private var model: PureModel

    nonisolated init(seed: Int) {
        _model = StateObject(wrappedValue: PureModel(seed: seed))
    }

    var body: some View {
        Text(String(model.seed))
    }
}

func constructExplicitOwner(seed: Int) -> ExplicitInitializerOwner {
    ExplicitInitializerOwner(seed: seed)
}
