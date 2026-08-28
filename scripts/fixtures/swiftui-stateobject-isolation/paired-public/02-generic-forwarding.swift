#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission case for the exact ordinary escaping thunk.
// Do not strengthen this parameter to qualify a different public contract.
func makeDeferredWrapper<Object: ObservableObject>(
    _ make: @escaping () -> Object
) -> StateObject<Object> {
    StateObject(wrappedValue: make())
}
