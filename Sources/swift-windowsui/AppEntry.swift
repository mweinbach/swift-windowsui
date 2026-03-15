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
        WindowGroup("Swift Windows UI") {
            DemoRootView(model: model)
        }
    }
}
