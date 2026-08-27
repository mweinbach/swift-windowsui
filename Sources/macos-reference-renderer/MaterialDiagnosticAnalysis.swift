import Foundation

/// Capture diagnostics, not a SwiftUI conformance oracle. The two spatial
/// frequencies distinguish filtering from a flat tint or missing/opaque content.
enum MaterialDiagnosticPlan {
    static let version = 1
    static let width = 384
    static let height = 288
    static let scale = 2
    static let stripeWidth = 4
    static let stripeEdgeInsetPixels = 2
    static let bandBoundary = 144
    static let repetitions = 2
    static let settlingMilliseconds = 50
    static let panel = Region(x: 24, y: 24, width: 336, height: 240)
    static let fineSample = Region(x: 96, y: 64, width: 192, height: 32)
    static let darkSample = Region(x: 64, y: 208, width: 16, height: 16)
    static let lightSample = Region(x: 304, y: 208, width: 16, height: 16)

    struct Region: Codable, Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    enum Fixture: String, CaseIterable, Codable {
        case pattern = "pattern-control"
        case tint = "flat-tint-control"
        case direct = "material-direct-control"
        case compositingGroup = "material-compositing-group"
        case drawingGroup = "material-drawing-group"
        case contentBlur = "material-content-blur"
    }
}

struct MaterialDiagnosticPixel {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var luma: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    var isValid: Bool {
        [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

struct MaterialDiagnosticMeasurements: Codable {
    let pixelWidth: Int
    let pixelHeight: Int
    let fineContrast: Double
    let fineDarkMean: Double
    let fineLightMean: Double
    let coarseContrast: Double
    let darkMean: Double
    let lightMean: Double
    let minimumSampleAlpha: Double

    var frequencyRatio: Double? {
        coarseContrast > 0.000_001 ? fineContrast / coarseContrast : nil
    }
}

struct MaterialDiagnosticThresholds: Encodable {
    let patternMinimumContrast = 0.5
    let patternMaximumDarkMean = 0.25
    let patternMinimumLightMean = 0.75
    let minimumSampleAlpha = 0.98
    let tintMinimumContrast = 0.15
    let tintMinimumRelativeFrequencyRatio = 0.8
    let tintMaximumRelativeFrequencyRatio = 1.2
    let tintMaximumCoarseRetention = 0.9
    let tintMinimumDarkMeanLift = 0.1
    let materialMinimumCoarseContrast = 0.04
    let materialMinimumCoarseRetention = 0.05
    let materialMaximumRelativeFrequencyRatio = 0.35
    let materialMaximumFrequencyRatioRelativeToTint = 0.4
    let maximumRepeatedMetricDifference = 0.02
}

struct MaterialDiagnosticControlResult: Codable {
    enum Status: String, Codable {
        case confirmed = "backdrop-filtering-observed"
        case inconclusive
    }

    let status: Status
    let reasons: [String]
    let flatTintRelativeFrequencyRatio: Double?
    let flatTintCoarseRetention: Double?
    let flatTintDarkMeanLift: Double?
    let materialRelativeFrequencyRatio: Double?
    let materialToTintFrequencyRatio: Double?
    let materialCoarseRetention: Double?
}

struct MaterialDiagnosticRepeatedControls {
    let status: MaterialDiagnosticControlResult.Status
    let reasons: [String]
    let repetitions: [MaterialDiagnosticControlResult]
}

enum MaterialDiagnosticAnalysis {
    enum Failure: Error, CustomStringConvertible {
        case extent
        case pixel

        var description: String {
            switch self {
            case .extent: return "Capture dimensions do not match the fixed 2x fixture plan."
            case .pixel: return "A sampled pixel is missing, nonfinite, or outside normalized sRGB."
            }
        }
    }

    /// Coordinates address the PNG's top row first. The pattern control also
    /// guards against a vertically inverted capture or the wrong output scale.
    static func measure(
        width: Int, height: Int,
        pixel: (Int, Int) -> MaterialDiagnosticPixel?
    ) throws -> MaterialDiagnosticMeasurements {
        let plan = MaterialDiagnosticPlan.self
        guard width == plan.width * plan.scale, height == plan.height * plan.scale else {
            throw Failure.extent
        }
        var minimumAlpha = 1.0
        func sample(_ x: Int, _ y: Int) throws -> Double {
            guard let value = pixel(x, y), value.isValid else { throw Failure.pixel }
            minimumAlpha = min(minimumAlpha, value.alpha)
            return value.luma
        }
        func mean(_ region: MaterialDiagnosticPlan.Region) throws -> Double {
            var sum = 0.0
            for y in region.y * plan.scale..<(region.y + region.height) * plan.scale {
                for x in region.x * plan.scale..<(region.x + region.width) * plan.scale {
                    sum += try sample(x, y)
                }
            }
            return sum / Double(region.width * region.height * plan.scale * plan.scale)
        }
        var fineSums = [0.0, 0.0]
        var fineCounts = [0, 0]
        var allFineSum = 0.0
        var allFineSquaredSum = 0.0
        var allFineCount = 0
        let fine = plan.fineSample
        for y in fine.y * plan.scale..<(fine.y + fine.height) * plan.scale {
            for x in fine.x * plan.scale..<(fine.x + fine.width) * plan.scale {
                let value = try sample(x, y)
                allFineSum += value
                allFineSquaredSum += value * value
                allFineCount += 1
                let withinStripe = x % (plan.stripeWidth * plan.scale)
                guard withinStripe >= plan.stripeEdgeInsetPixels,
                    withinStripe < plan.stripeWidth * plan.scale - plan.stripeEdgeInsetPixels
                else { continue }
                let stripe = (x / (plan.stripeWidth * plan.scale)) % 2
                fineSums[stripe] += value
                fineCounts[stripe] += 1
            }
        }
        let dark = try mean(plan.darkSample)
        let light = try mean(plan.lightSample)
        let fineDark = fineSums[0] / Double(fineCounts[0])
        let fineLight = fineSums[1] / Double(fineCounts[1])
        let fineMean = allFineSum / Double(allFineCount)
        let fineVariance = max(0, allFineSquaredSum / Double(allFineCount) - fineMean * fineMean)
        // Twice the standard deviation equals two-level stripe contrast but
        // cannot disappear merely because a sharp pattern changed phase.
        // Phase means above validate only the known bare-pattern geometry.
        let fineContrast = min(1, 2 * fineVariance.squareRoot())
        return MaterialDiagnosticMeasurements(
            pixelWidth: width, pixelHeight: height,
            fineContrast: fineContrast, fineDarkMean: fineDark, fineLightMean: fineLight,
            coarseContrast: abs(light - dark), darkMean: dark, lightMean: light,
            minimumSampleAlpha: minimumAlpha)
    }

    /// Conservative evidence thresholds, not expected native material pixels.
    /// Retained coarse contrast rejects opaque fills; a working tint control
    /// rejects mistaking ordinary alpha attenuation for spatial filtering.
    static func evaluateControls(
        _ measurements: [MaterialDiagnosticPlan.Fixture: MaterialDiagnosticMeasurements]
    ) -> MaterialDiagnosticControlResult {
        guard let pattern = measurements[.pattern], let tint = measurements[.tint],
            let material = measurements[.direct]
        else {
            return MaterialDiagnosticControlResult(
                status: .inconclusive, reasons: ["One or more control captures could not be measured."],
                flatTintRelativeFrequencyRatio: nil, flatTintCoarseRetention: nil, flatTintDarkMeanLift: nil,
                materialRelativeFrequencyRatio: nil,
                materialToTintFrequencyRatio: nil, materialCoarseRetention: nil)
        }
        let thresholds = MaterialDiagnosticThresholds()
        var reasons: [String] = []
        if pattern.fineContrast < thresholds.patternMinimumContrast
            || pattern.coarseContrast < thresholds.patternMinimumContrast
            || pattern.darkMean > thresholds.patternMaximumDarkMean
            || pattern.lightMean < thresholds.patternMinimumLightMean
            || pattern.fineDarkMean > thresholds.patternMaximumDarkMean
            || pattern.fineLightMean < thresholds.patternMinimumLightMean
        {
            reasons.append("The patterned control does not establish the expected orientation and contrast.")
        }
        if [pattern, tint, material].contains(where: { $0.minimumSampleAlpha < thresholds.minimumSampleAlpha }) {
            reasons.append("A control is not opaque over the fixture's opaque patterned backdrop.")
        }
        let patternRatio = pattern.frequencyRatio
        let tintRatio = relativeRatio(tint.frequencyRatio, to: patternRatio)
        let materialRatio = relativeRatio(material.frequencyRatio, to: patternRatio)
        let materialToTint = relativeRatio(material.frequencyRatio, to: tint.frequencyRatio)
        let tintRetention = pattern.coarseContrast > 0.000_001 ? tint.coarseContrast / pattern.coarseContrast : nil
        let tintLift = tint.darkMean - pattern.darkMean
        let tintRange = thresholds.tintMinimumRelativeFrequencyRatio...thresholds.tintMaximumRelativeFrequencyRatio
        if tint.coarseContrast < thresholds.tintMinimumContrast || tint.fineContrast < thresholds.tintMinimumContrast
            || tintRatio.map({ !tintRange.contains($0) }) ?? true
        {
            reasons.append("The flat-tint control does not retain both spatial frequencies as expected.")
        }
        if tintRetention.map({ $0 > thresholds.tintMaximumCoarseRetention }) ?? true
            || tintLift < thresholds.tintMinimumDarkMeanLift
        {
            reasons.append("The flat-tint control does not establish that its white overlay was captured.")
        }
        let retention =
            pattern.coarseContrast > 0.000_001
            ? material.coarseContrast / pattern.coarseContrast : nil
        if material.coarseContrast < thresholds.materialMinimumCoarseContrast
            || retention.map({ $0 < thresholds.materialMinimumCoarseRetention }) ?? true
        {
            reasons.append("The ordinary material does not retain enough coarse backdrop variation.")
        }
        if materialRatio.map({ $0 > thresholds.materialMaximumRelativeFrequencyRatio }) ?? true
            || materialToTint.map({ $0 > thresholds.materialMaximumFrequencyRatioRelativeToTint }) ?? true
        {
            reasons.append("The ordinary material does not selectively attenuate the fine pattern enough.")
        }
        return MaterialDiagnosticControlResult(
            status: reasons.isEmpty ? .confirmed : .inconclusive, reasons: reasons,
            flatTintRelativeFrequencyRatio: tintRatio, flatTintCoarseRetention: tintRetention,
            flatTintDarkMeanLift: tintLift, materialRelativeFrequencyRatio: materialRatio,
            materialToTintFrequencyRatio: materialToTint, materialCoarseRetention: retention)
    }

    private static func relativeRatio(_ value: Double?, to baseline: Double?) -> Double? {
        guard let value, let baseline, baseline > 0.000_001 else { return nil }
        return value / baseline
    }

    static func areStable(_ first: MaterialDiagnosticMeasurements, _ second: MaterialDiagnosticMeasurements) -> Bool {
        let limit = MaterialDiagnosticThresholds().maximumRepeatedMetricDifference
        return first.pixelWidth == second.pixelWidth && first.pixelHeight == second.pixelHeight
            && abs(first.fineContrast - second.fineContrast) <= limit
            && abs(first.fineDarkMean - second.fineDarkMean) <= limit
            && abs(first.fineLightMean - second.fineLightMean) <= limit
            && abs(first.coarseContrast - second.coarseContrast) <= limit
            && abs(first.darkMean - second.darkMean) <= limit
            && abs(first.lightMean - second.lightMean) <= limit
            && abs(first.minimumSampleAlpha - second.minimumSampleAlpha) <= limit
    }

    static func evaluateRepeatedControls(
        _ measurements: [[MaterialDiagnosticPlan.Fixture: MaterialDiagnosticMeasurements]]
    ) -> MaterialDiagnosticRepeatedControls {
        let evaluations = measurements.map(evaluateControls)
        var reasons = evaluations.enumerated().flatMap { index, result in
            result.reasons.map { "Repetition \(index + 1): \($0)" }
        }
        if measurements.count != MaterialDiagnosticPlan.repetitions {
            reasons.append("The fixed number of control repetitions was not captured.")
        }
        for fixture: MaterialDiagnosticPlan.Fixture in [.pattern, .tint, .direct] {
            let samples = measurements.compactMap { $0[fixture] }
            if samples.count != MaterialDiagnosticPlan.repetitions || !areStable(samples[0], samples[1]) {
                reasons.append("Control \(fixture.rawValue) did not produce stable repeated measurements.")
            }
        }
        return MaterialDiagnosticRepeatedControls(
            status: reasons.isEmpty && evaluations.allSatisfy { $0.status == .confirmed } ? .confirmed : .inconclusive,
            reasons: reasons, repetitions: evaluations)
    }
}
