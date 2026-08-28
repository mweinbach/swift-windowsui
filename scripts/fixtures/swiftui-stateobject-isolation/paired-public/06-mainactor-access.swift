#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission control: both accessors are used on their required actor.
@MainActor
func readWrapperOnMainActor(_ wrapper: StateObject<PureModel>) -> PureModel {
    let object = wrapper.wrappedValue
    _ = wrapper.projectedValue
    return object
}
