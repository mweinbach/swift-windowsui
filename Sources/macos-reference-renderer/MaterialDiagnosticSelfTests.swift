import Foundation

/// Portable classifier and metadata checks. These synthetic values are never
/// native observations and cannot establish what SwiftUI renders on macOS.
enum MaterialDiagnosticSelfTests {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else {
                throw NSError(
                    domain: "MaterialDiagnosticSelfTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name])
            }
            count += 1
        }
        func measure(
            fine: Double, coarse: Double, center: Double = 0.5, alpha: Double = 1,
            inverted: Bool = false, phaseShiftPixels: Int = 0
        ) throws -> MaterialDiagnosticMeasurements {
            try MaterialDiagnosticAnalysis.measure(
                width: MaterialDiagnosticPlan.width * MaterialDiagnosticPlan.scale,
                height: MaterialDiagnosticPlan.height * MaterialDiagnosticPlan.scale,
                pixel: { x, pixelY in
                    let y =
                        inverted ? MaterialDiagnosticPlan.height * MaterialDiagnosticPlan.scale - pixelY - 1 : pixelY
                    let stripe =
                        (x + phaseShiftPixels) / (MaterialDiagnosticPlan.stripeWidth * MaterialDiagnosticPlan.scale) % 2
                    let top = y < MaterialDiagnosticPlan.bandBoundary * MaterialDiagnosticPlan.scale
                    let isLight =
                        top ? stripe == 1 : x >= MaterialDiagnosticPlan.width * MaterialDiagnosticPlan.scale / 2
                    let contrast = top ? fine : coarse
                    let value = center + (isLight ? contrast : -contrast) / 2
                    return MaterialDiagnosticPixel(red: value, green: value, blue: value, alpha: alpha)
                })
        }
        let pattern = try measure(fine: 0.8, coarse: 0.8)
        let tint = try measure(fine: 0.48, coarse: 0.48, center: 0.7)
        let filtered = try measure(fine: 0.01, coarse: 0.3)
        func controls(
            _ material: MaterialDiagnosticMeasurements,
            pattern source: MaterialDiagnosticMeasurements = pattern,
            tint negative: MaterialDiagnosticMeasurements = tint
        ) -> MaterialDiagnosticControlResult {
            MaterialDiagnosticAnalysis.evaluateControls([.pattern: source, .tint: negative, .direct: material])
        }
        try check(abs(pattern.fineContrast - 0.8) < 0.000_001, "Fine-pattern measurement")
        try check(abs(pattern.coarseContrast - 0.8) < 0.000_001, "Coarse-pattern measurement")
        try check(controls(filtered).status == .confirmed, "Selective filtering positive control")
        try check(controls(tint).status == .inconclusive, "A flat tint is not backdrop filtering")
        try check(controls(filtered, tint: pattern).status == .inconclusive, "A missing tint overlay is inconclusive")
        for phase in [1, 2, 4, 8] {
            let shifted = try measure(fine: 0.8, coarse: 0.8, phaseShiftPixels: phase)
            try check(
                abs(shifted.fineContrast - pattern.fineContrast) < 0.000_001,
                "Fine contrast is independent of sharp stripe phase")
            try check(controls(shifted).status == .inconclusive, "Sharp shifted stripes are not backdrop filtering")
        }
        try check(
            controls(try measure(fine: 0.3, coarse: 0.3, center: 0.45)).status == .inconclusive,
            "A pointwise color mapping is not spatial filtering")
        try check(controls(pattern).status == .inconclusive, "Missing material is inconclusive")
        try check(controls(try measure(fine: 0, coarse: 0)).status == .inconclusive, "Opaque fill is inconclusive")
        try check(
            controls(try measure(fine: 0, coarse: 0, center: 0, alpha: 0)).status == .inconclusive,
            "Empty transparent output is inconclusive")
        try check(
            controls(try measure(fine: 0.001, coarse: 0.01)).status == .inconclusive,
            "Nearly opaque fill is inconclusive")
        try check(
            controls(try measure(fine: 0.01, coarse: 0.3, alpha: 0.5)).status == .inconclusive,
            "Transparent capture is inconclusive")
        try check(
            controls(filtered, pattern: try measure(fine: 0.8, coarse: 0.8, inverted: true)).status == .inconclusive,
            "Inverted capture is inconclusive")
        try check(
            controls(filtered, tint: filtered).status == .inconclusive, "Filtering the negative control is inconclusive"
        )
        try check(
            MaterialDiagnosticAnalysis.evaluateControls([.pattern: pattern]).status == .inconclusive,
            "Missing capture is inconclusive")
        try check(MaterialDiagnosticAnalysis.areStable(filtered, filtered), "Stable repetitions")
        try check(!MaterialDiagnosticAnalysis.areStable(filtered, tint), "Drifting repetitions")
        let firstControls: [MaterialDiagnosticPlan.Fixture: MaterialDiagnosticMeasurements] = [
            .pattern: pattern, .tint: tint, .direct: filtered,
        ]
        let driftingControls: [MaterialDiagnosticPlan.Fixture: MaterialDiagnosticMeasurements] = [
            .pattern: pattern, .tint: tint, .direct: try measure(fine: 0.01, coarse: 0.25),
        ]
        try check(
            MaterialDiagnosticAnalysis.evaluateRepeatedControls([firstControls, firstControls]).status == .confirmed,
            "Repeated positive controls")
        try check(
            MaterialDiagnosticAnalysis.evaluateRepeatedControls([firstControls, driftingControls]).status
                == .inconclusive, "Individually positive but unstable controls")
        try check(
            MaterialDiagnosticAnalysis.evaluateRepeatedControls([firstControls]).status == .inconclusive,
            "Missing repetition is inconclusive")
        try check(
            MaterialDiagnosticAnalysis.evaluateRepeatedControls([]).status == .inconclusive,
            "Empty capture run is inconclusive")
        do {
            _ = try MaterialDiagnosticAnalysis.measure(width: 384, height: 288, pixel: { _, _ in nil })
            try check(false, "Unexpected capture scale must fail")
        } catch MaterialDiagnosticAnalysis.Failure.extent {
            count += 1
        }
        do {
            _ = try MaterialDiagnosticAnalysis.measure(
                width: 768, height: 576,
                pixel: { _, _ in MaterialDiagnosticPixel(red: .nan, green: 0, blue: 0, alpha: 1) })
            try check(false, "Invalid pixels must fail")
        } catch MaterialDiagnosticAnalysis.Failure.pixel {
            count += 1
        }
        let data = try JSONEncoder().encode(controls(filtered))
        let decoded = try JSONDecoder().decode(MaterialDiagnosticControlResult.self, from: data)
        try check(decoded.status == .confirmed && decoded.reasons.isEmpty, "Control result JSON round trip")

        func object(_ value: some Encodable) throws -> [String: Any] {
            let data = try JSONEncoder().encode(value)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(
                    domain: "MaterialDiagnosticSelfTests", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Metadata must encode a JSON object"])
            }
            return result
        }
        var environment = MaterialDiagnosticMetadata.EnvironmentObservation()
        let unobserved = environment
        let unknownJSON = try object(unobserved)
        try check(
            unobserved.status == "unobserved" && unobserved.bodyEvaluationCount == 0,
            "No body evaluation is explicitly unobserved")
        try check(
            unknownJSON["values"] is NSNull && unknownJSON["latestBodyEvaluationUTC"] is NSNull,
            "Unknown effective environment values encode as null, not requested defaults")
        let effective = MaterialDiagnosticMetadata.EnvironmentValues(
            reduceTransparency: false, reduceMotion: false, colorScheme: "light",
            colorSchemeContrast: "standard", displayScale: 2)
        environment.record(effective, timestampUTC: "synthetic-first-evaluation")
        let firstObservation = environment
        let observedJSON = try object(firstObservation)
        let observedValues = observedJSON["values"] as? [String: Any]
        try check(
            observedJSON["status"] as? String == "observed"
                && observedValues?["reduceTransparency"] as? Bool == false
                && observedValues?["reduceMotion"] as? Bool == false,
            "Observed false accessibility flags are distinct from unknown")
        try check(
            firstObservation.bodyEvaluationCount == 1
                && firstObservation.latestBodyEvaluationUTC == "synthetic-first-evaluation",
            "Effective values retain the actual body evaluation count and timestamp")
        try check(environment == firstObservation, "Reading a snapshot does not invent a fresh body evaluation")
        environment.record(
            MaterialDiagnosticMetadata.EnvironmentValues(
                reduceTransparency: true, reduceMotion: true, colorScheme: "unknown",
                colorSchemeContrast: "unknown", displayScale: 1),
            timestampUTC: "synthetic-second-evaluation")
        try check(
            environment.bodyEvaluationCount == 2
                && environment.latestBodyEvaluationUTC == "synthetic-second-evaluation"
                && environment.values?.reduceTransparency == true,
            "A later body evaluation replaces values and advances provenance")
        try check(
            unobserved.values == nil && firstObservation.values == effective,
            "Before and after snapshots do not alias the recorder's mutable state")

        let unavailableBitmap = MaterialDiagnosticMetadata.BitmapRecommendation(bitmap: nil)
        let unavailableJSON = try object(unavailableBitmap)
        try check(
            unavailableJSON["status"] as? String == "unavailable" && unavailableJSON["bitmap"] is NSNull,
            "A missing recommended bitmap has an explicit unavailable state")
        let recommendation = MaterialDiagnosticMetadata.BitmapRecommendation(
            bitmap: MaterialDiagnosticMetadata.Bitmap(
                pixelWidth: 384, pixelHeight: 288, logicalWidth: 384, logicalHeight: 288,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                bitsPerPixel: 32, bytesPerRow: 1_536, bitmapFormatRawValue: 0, colorSpaceName: "synthetic-RGB"))
        let bitmapJSON = try object(recommendation)["bitmap"] as? [String: Any]
        try check(
            recommendation.status == "observed" && bitmapJSON?["pixelWidth"] as? Int == 384
                && bitmapJSON?["bytesPerRow"] as? Int == 1_536 && bitmapJSON?["bitmapFormatRawValue"] as? UInt == 0,
            "Recommended bitmap metadata preserves its actual dimensions and format")
        try check(
            MaterialDiagnosticPlan.scale == 2 && MaterialDiagnosticPlan.width * MaterialDiagnosticPlan.scale == 768,
            "A diagnostic 1x recommendation does not replace the 2x capture plan")

        let bounds = MaterialDiagnosticMetadata.Rectangle(x: 0, y: 0, width: 384, height: 288)
        let host = MaterialDiagnosticMetadata.Host(
            hasWindow: false, hasSuperview: false, isHidden: false, isHiddenOrHasHiddenAncestor: false,
            isFlipped: true, effectiveAppearance: "synthetic-aqua", frame: bounds, bounds: bounds,
            visibleRect: bounds, convertedBackingBounds: bounds, wantsLayer: false, hasLayer: false,
            layerContentsScale: nil, window: nil)
        let application = MaterialDiagnosticMetadata.Application(
            activationPolicy: "prohibited", isActive: false, isHidden: false, isRunning: false)
        let before = MaterialDiagnosticMetadata.Snapshot(
            timestampUTC: "synthetic-before",
            systemAccessibility: MaterialDiagnosticMetadata.SystemAccessibility(
                reduceTransparency: true, increaseContrast: false, reduceMotion: true),
            swiftUIEnvironment: unobserved, application: application, host: host)
        let after = MaterialDiagnosticMetadata.Snapshot(
            timestampUTC: "synthetic-after",
            systemAccessibility: MaterialDiagnosticMetadata.SystemAccessibility(
                reduceTransparency: false, increaseContrast: true, reduceMotion: true),
            swiftUIEnvironment: firstObservation, application: application, host: host)
        let capture = MaterialDiagnosticMetadata.Capture(
            before: before, after: after, cacheDisplayCompleted: true, recommendedBitmap: recommendation)
        let captureJSON = try object(capture)
        let beforeJSON = captureJSON["before"] as? [String: Any]
        let afterJSON = captureJSON["after"] as? [String: Any]
        try check(
            captureJSON["schemaVersion"] as? Int == 1 && captureJSON["cacheDisplayCompleted"] as? Bool == true
                && beforeJSON?["timestampUTC"] as? String == "synthetic-before"
                && afterJSON?["timestampUTC"] as? String == "synthetic-after",
            "Per-capture provenance retains both timestamped observations")
        let beforeFlags = beforeJSON?["systemAccessibility"] as? [String: Any]
        let afterFlags = afterJSON?["systemAccessibility"] as? [String: Any]
        try check(
            beforeFlags?["reduceTransparency"] as? Bool == true
                && afterFlags?["reduceTransparency"] as? Bool == false,
            "System flags are sampled separately before and after a capture")
        try check(
            after.systemAccessibility.reduceMotion && after.swiftUIEnvironment.values?.reduceMotion == false,
            "System preferences never substitute for observed SwiftUI environment values")
        let hostJSON = afterJSON?["host"] as? [String: Any]
        try check(
            hostJSON?["hasWindow"] as? Bool == false && hostJSON?["window"] == nil
                && hostJSON?["hasLayer"] as? Bool == false && hostJSON?["layerContentsScale"] == nil,
            "An unattached host does not invent window visibility or layer backing values")
        let failed = MaterialDiagnosticMetadata.Capture(
            before: before, after: before, cacheDisplayCompleted: false, recommendedBitmap: unavailableBitmap)
        let failedJSON = try object(failed)
        try check(
            failedJSON["cacheDisplayCompleted"] as? Bool == false
                && failed.before.swiftUIEnvironment.status == "unobserved"
                && failed.after.swiftUIEnvironment.status == "unobserved",
            "An incomplete capture can retain unknown provenance without fabricated observations")
        return count
    }
}
