#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Admission case: create on one actor, transfer, and read only on MainActor.
// These declarations are compiled, never invoked by this source matrix.
actor PureWrapperProducer {
    func makeWrapper(seed: Int) -> StateObject<PureModel> {
        StateObject(wrappedValue: PureModel(seed: seed))
    }
}

@MainActor
func consumeProducedWrapper(_ producer: PureWrapperProducer) async -> Int {
    let wrapper = await producer.makeWrapper(seed: 5)
    return wrapper.wrappedValue.seed
}
