#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// Interaction readouts belong to one window's retained view tree. The root
/// owns this object above the tabs; authored app preferences remain shared in
/// DemoDashboardModel and DemoGalleryState.
@MainActor
final class DemoWindowState: ObservableObject {
    let observation = DemoObservationState()
}
