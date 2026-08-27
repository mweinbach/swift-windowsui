#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// The same settings form can live in the demo's navigation or an independent
/// Settings scene. The model supplies persistence and validation in both cases.
public struct DemoSettingsTemplate: View {
    @ObservedObject private var model: DemoDashboardModel

    public init(model: DemoDashboardModel) {
        self.model = model
    }

    public var body: some View {
        DemoSettingsScreen(model: model)
            .preferredColorScheme(model.theme.colorScheme)
            .tint(model.accentColor)
            .dynamicTypeSize(model.dynamicTypeSize)
            .frame(minWidth: 640, minHeight: 480)
    }
}
