#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission case. The client's default isolation must be nonisolated.
// No wrapped value, projection, or body is accessed here.
func makeDirectWrapper() -> StateObject<PureModel> {
    StateObject(wrappedValue: PureModel(seed: 1))
}
