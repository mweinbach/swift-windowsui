import Foundation

/// Portable classifier checks. These synthetic pixels are never native
/// reference images and cannot establish what SwiftUI renders on macOS.
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
        return count
    }
}
