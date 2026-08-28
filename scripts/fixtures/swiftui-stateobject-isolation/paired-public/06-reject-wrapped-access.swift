#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Rejection case: the diagnostic must concern wrappedValue isolation,
// not model construction, a body, or the projection's platform-specific type.
func rejectWrappedAccess(_ wrapper: StateObject<PureModel>) -> PureModel {
    wrapper.wrappedValue
}
