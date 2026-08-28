#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

// Intentional protocol confound: no explicit actor annotation or special
// initializer. Compare the platform's ObservableObject inference separately.
public final class OrdinaryProbeModel: ObservableObject {
    public var value: Int

    public init(seed: Int) {
        self.value = seed
    }
}
