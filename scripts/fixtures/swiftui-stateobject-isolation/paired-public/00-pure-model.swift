#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Shared model: constructing it must not introduce an unrelated actor diagnostic.
@MainActor
public final class PureModel: ObservableObject {
    public let seed: Int

    public nonisolated init(seed: Int) {
        self.seed = seed
    }
}
