#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Source observation only. Construct the Scene value without evaluating body.
// Its declaration does not establish a Scene-owned object lifetime.
@MainActor
struct SynthesizedInitializerScene: Scene {
    @StateObject private var model = PureModel(seed: 1)

    var body: some Scene {
        WindowGroup("Synthesized initializer Scene probe") {
            Text(String(model.seed))
        }
    }
}

func constructSynthesizedScene() -> SynthesizedInitializerScene {
    SynthesizedInitializerScene()
}
