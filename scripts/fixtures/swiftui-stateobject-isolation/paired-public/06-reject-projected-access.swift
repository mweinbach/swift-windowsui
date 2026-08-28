#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Rejection case: discard the projection so differing public projection
// types cannot introduce an unrelated conversion diagnostic.
func rejectProjectedAccess(_ wrapper: StateObject<PureModel>) {
    _ = wrapper.projectedValue
}
