#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission control: construct the same synthesized owner on MainActor.
// There is still no explicit initializer.
@MainActor
struct SynthesizedInitializerOwner: View {
    @StateObject private var model = PureModel(seed: 1)

    var body: some View {
        Text(String(model.seed))
    }
}

@MainActor
func constructSynthesizedOwner() -> SynthesizedInitializerOwner {
    SynthesizedInitializerOwner()
}
