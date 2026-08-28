#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Source observation only: no entry-point attribute or invocation of App.main.
// The body declaration does not establish an App-owned object lifetime.
@MainActor
struct SynthesizedInitializerApp: App {
    @StateObject private var model = PureModel(seed: 1)

    var body: some Scene {
        WindowGroup("Synthesized initializer App probe") {
            Text(String(model.seed))
        }
    }
}

func constructSynthesizedApp() -> SynthesizedInitializerApp {
    SynthesizedInitializerApp()
}
