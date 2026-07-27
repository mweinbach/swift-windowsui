import SwiftWindowsDemo

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif
@main
struct SwiftWindowsUIDemoApp: App {
    private let model = DemoDashboardModel()

    init() {}

    var body: some Scene {
        // The id registers the scene with the window coordinator so the
        // settings screen's `openWindow(id:)` can spawn additional windows
        // hosting the same content.
        WindowGroup("Swift Windows UI", id: "main-dashboard") {
            DemoRootView(model: model)
        }
    }
}
