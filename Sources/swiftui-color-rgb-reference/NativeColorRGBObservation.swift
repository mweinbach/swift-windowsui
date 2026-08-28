#if os(macOS)
    import AppKit
    import SwiftUI

    @MainActor
    enum NativeColorRGBObservation {
        static func resolved(_ fixture: RGBConstructorCase) -> [RGBObservation] {
            let color = fixture.makeColor()
            let environments: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]
            return environments.map { name, colorScheme in
                var environment = EnvironmentValues()
                environment.colorScheme = colorScheme
                let resolved = color.resolve(in: environment)
                // These public getters are encoded sRGB. The distinct linear
                // getters below are diagnostics, not an encoding oracle.
                return .observed(
                    environment: name,
                    encodedRGBA: RGBEncodedComponents(
                        red: resolved.red, green: resolved.green, blue: resolved.blue, alpha: resolved.opacity),
                    linearRGB: RGBLinearComponents(
                        red: resolved.linearRed, green: resolved.linearGreen, blue: resolved.linearBlue))
            }
        }

        static func appKit(_ fixture: RGBConstructorCase) -> [RGBObservation] {
            let color = fixture.makeColor()
            let target = NSColorSpace.extendedSRGB
            guard let converted = NSColor(color).usingColorSpace(target) else {
                return [.unsupported(reason: "color-space-conversion-unavailable")]
            }

            let actualSpace = converted.colorSpace
            let identityMatches = actualSpace.isEqual(target)
            let isRGB = actualSpace.colorSpaceModel == .rgb
            // Only component colors support numberOfComponents/getComponents.
            // Do not ask a surprising non-RGB result to expose RGB components.
            let count = isRGB ? converted.numberOfComponents : nil
            let spaceRecord = RGBAppKitSpaceRecord(
                targetColorSpace: "extendedSRGB",
                actualColorSpaceName: actualSpace.localizedName ?? "",
                colorSpaceModel: isRGB ? "rgb" : "non-rgb(\(actualSpace.colorSpaceModel.rawValue))",
                componentCount: count,
                targetIdentityMatches: identityMatches)
            guard isRGB else {
                return [.unsupported(reason: "unexpected-color-space-model", appKit: spaceRecord)]
            }
            guard identityMatches else {
                return [.unsupported(reason: "unexpected-color-space-identity", appKit: spaceRecord)]
            }
            guard count == 4 else {
                return [.unsupported(reason: "unexpected-component-count", appKit: spaceRecord)]
            }

            var components = [CGFloat](repeating: .nan, count: 4)
            components.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                converted.getComponents(baseAddress)
            }
            return [
                .observed(
                    environment: "none",
                    encodedRGBA: RGBEncodedComponents(
                        red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]),
                        alpha: Double(components[3])),
                    appKit: spaceRecord)
            ]
        }
    }
#endif
