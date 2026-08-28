#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Source observation: record synthesized initializer and default-expression isolation.
// There is no explicit initializer and no unrelated stored property.
@MainActor
struct SynthesizedInitializerOwner: View {
    @StateObject private var model = PureModel(seed: 1)

    var body: some View {
        Text(String(model.seed))
    }
}

func constructSynthesizedOwner() -> SynthesizedInitializerOwner {
    SynthesizedInitializerOwner()
}
