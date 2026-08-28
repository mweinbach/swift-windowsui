#if os(Windows)
    import WinSwiftUI

    @MainActor
    enum WindowsColorRGBObservation {
        static func observe(_ fixture: RGBConstructorCase) -> [RGBObservation] {
            let color = fixture.makeColor()
            // Read the public retained fields, not the conversion helper or
            // Windows Color.Resolved. Their separate API is not under test.
            return [
                .observed(
                    environment: "none",
                    encodedRGBA: RGBEncodedComponents(
                        red: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
            ]
        }
    }
#endif
