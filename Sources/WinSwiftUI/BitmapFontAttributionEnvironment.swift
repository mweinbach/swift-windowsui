import SwiftWindowsUI

@MainActor
final class BitmapFontAttributionLink {
    weak var session: NativeBitmapFontAttributionSession?

    init(_ session: NativeBitmapFontAttributionSession) {
        self.session = session
    }
}

private enum BitmapFontAttributionEnvironmentKey: EnvironmentKey {
    static let defaultValue: BitmapFontAttributionLink? = nil
}

extension EnvironmentValues {
    var bitmapFontAttributionLink: BitmapFontAttributionLink? {
        get { self[BitmapFontAttributionEnvironmentKey.self] }
        set { self[BitmapFontAttributionEnvironmentKey.self] = newValue }
    }

    @MainActor
    var bitmapFontAttribution: NativeBitmapFontAttributionSession? {
        get { bitmapFontAttributionLink?.session }
        set {
            bitmapFontAttributionLink = newValue.map(BitmapFontAttributionLink.init)
        }
    }
}

extension ViewBuildContext {
    var bitmapFontAttribution: NativeBitmapFontAttributionSession? {
        environmentValues.bitmapFontAttribution
    }
}
