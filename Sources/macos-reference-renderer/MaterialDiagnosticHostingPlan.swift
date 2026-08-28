import Foundation

/// A predeclared, opt-in diagnostic protocol. It does not change the canonical
/// fixtures, classify native semantics, or require any AppKit object.
enum MaterialDiagnosticHostingPlan {
    static let version = 1
    static let fileName = "hosting-experiment.json"
    static let canonicalCaptureCount = 12

    enum Arm: String, CaseIterable, Codable {
        case unattached = "accessory-unattached"
        case unshownWindow = "accessory-unshown-window"
    }

    struct Attempt: Encodable, Equatable {
        let ordinal: Int
        let pairIndex: Int
        let positionInPair: Int
        let arm: Arm
        let fixture: MaterialDiagnosticPlan.Fixture
        let repetition: Int

        var pngFile: String { "\(arm.rawValue)-\(fixture.rawValue)-\(repetition).png" }

        private enum CodingKeys: String, CodingKey {
            case ordinal, pairIndex, positionInPair, arm, fixture, repetition, pngFile
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(ordinal, forKey: .ordinal)
            try values.encode(pairIndex, forKey: .pairIndex)
            try values.encode(positionInPair, forKey: .positionInPair)
            try values.encode(arm, forKey: .arm)
            try values.encode(fixture, forKey: .fixture)
            try values.encode(repetition, forKey: .repetition)
            try values.encode(pngFile, forKey: .pngFile)
        }
    }

    static var attempts: [Attempt] {
        var result: [Attempt] = []
        for (fixtureIndex, fixture) in MaterialDiagnosticPlan.Fixture.allCases.enumerated() {
            for repetition in 1...MaterialDiagnosticPlan.repetitions {
                let arms: [Arm] = repetition == 1 ? [.unattached, .unshownWindow] : [.unshownWindow, .unattached]
                for (position, arm) in arms.enumerated() {
                    result.append(
                        Attempt(
                            ordinal: result.count + 1, pairIndex: fixtureIndex * 2 + repetition,
                            positionInPair: position + 1, arm: arm, fixture: fixture, repetition: repetition))
                }
            }
        }
        return result
    }

    struct Parameters: Encodable {
        let logicalWidth = MaterialDiagnosticPlan.width
        let logicalHeight = MaterialDiagnosticPlan.height
        let requestedScale = MaterialDiagnosticPlan.scale
        let requestedAppearance = "light / NSAppearance.aqua"
        let material = "regularMaterial"
        let repetitions = MaterialDiagnosticPlan.repetitions
        let settlingMillisecondsBeforeEachCapture = MaterialDiagnosticPlan.settlingMilliseconds
        let stripeWidthPoints = MaterialDiagnosticPlan.stripeWidth
        let patternBandBoundaryPoints = MaterialDiagnosticPlan.bandBoundary
        let baselinePhaseSampleInsetPixels = MaterialDiagnosticPlan.stripeEdgeInsetPixels
        let patternDarkSRGB = 0.1
        let patternLightSRGB = 0.9
        let panel = MaterialDiagnosticPlan.panel
        let fineSample = MaterialDiagnosticPlan.fineSample
        let darkSample = MaterialDiagnosticPlan.darkSample
        let lightSample = MaterialDiagnosticPlan.lightSample
        let thresholds = MaterialDiagnosticThresholds()
    }

    struct Qualification: Encodable {
        let nativeBehaviorReviewed = false
        let nativeRuntimeBuildReviewed = false
        let releaseQualified = false
    }

    struct Sample {
        let attempt: Attempt
        let measurements: MaterialDiagnosticMeasurements?
    }

    /// Both native reporting and portable checks use this arm boundary. A
    /// missing, duplicate, or malformed scheduled sample cannot borrow a
    /// control from the other arm to create a positive result.
    static func evaluateControls(arm: Arm, samples: [Sample]) -> MaterialDiagnosticRepeatedControls {
        let schedule = attempts
        let repeated = (1...MaterialDiagnosticPlan.repetitions).map { repetition in
            var values: [MaterialDiagnosticPlan.Fixture: MaterialDiagnosticMeasurements] = [:]
            var seen: Set<MaterialDiagnosticPlan.Fixture> = []
            for sample in samples where sample.attempt.arm == arm && sample.attempt.repetition == repetition {
                guard schedule.contains(sample.attempt), seen.insert(sample.attempt.fixture).inserted else {
                    return [MaterialDiagnosticPlan.Fixture: MaterialDiagnosticMeasurements]()
                }
                values[sample.attempt.fixture] = sample.measurements
            }
            return values
        }
        return MaterialDiagnosticAnalysis.evaluateRepeatedControls(repeated)
    }

    /// Check what was actually observed. Backing scale, occlusion, accessibility,
    /// and body evaluation timing are recorded without forcing their values.
    static func protocolFailures(
        _ snapshot: MaterialDiagnosticMetadata.Snapshot, arm: Arm
    ) -> [String] {
        var failures: [String] = []
        if snapshot.application.activationPolicy != "accessory" {
            failures.append("The application is not observed with accessory activation policy.")
        }
        if snapshot.application.isActive {
            failures.append("The application became active.")
        }
        let host = snapshot.host
        if !isExpectedRectangle(host.frame) || !isExpectedRectangle(host.bounds) {
            failures.append("Host frame or bounds differ from the fixed logical fixture extent.")
        }
        if host.effectiveAppearance != "NSAppearanceNameAqua" || !host.isFlipped {
            failures.append("Host appearance or orientation differs from the canonical fixture.")
        }
        if let environment = snapshot.swiftUIEnvironment.values,
            environment.colorScheme != "light" || environment.displayScale != Double(MaterialDiagnosticPlan.scale)
        {
            failures.append("The observed SwiftUI color scheme or display scale differs from the requested fixture.")
        }
        switch arm {
        case .unattached:
            if host.hasWindow || host.window != nil || host.hasSuperview {
                failures.append("The unattached arm acquired a window or superview.")
            }
        case .unshownWindow:
            if !host.hasWindow || host.window == nil {
                failures.append("The window arm has no observed host window.")
            }
            if let window = host.window, window.isVisible || window.isKeyWindow || window.isMainWindow {
                failures.append("The owned window became visible, key, or main.")
            }
        }
        return failures
    }

    private static func isExpectedRectangle(_ value: MaterialDiagnosticMetadata.Rectangle) -> Bool {
        value.x == 0 && value.y == 0
            && value.width == Double(MaterialDiagnosticPlan.width)
            && value.height == Double(MaterialDiagnosticPlan.height)
    }
}

/// The same scoped coordinator is used by native capture and portable injected
/// failure checks. State belongs to this run; no observable or global UI state.
@MainActor
final class MaterialDiagnosticHostingSession {
    enum Policy: String {
        case prohibited
        case accessory
    }

    struct PolicyChange: Encodable {
        let requestedPolicy: String
        let returnedSuccess: Bool
        let observedApplication: MaterialDiagnosticMetadata.Application
    }

    struct Failure: Encodable {
        let stage: String
        let message: String
        let captureOrdinal: Int?

        private enum CodingKeys: String, CodingKey { case stage, message, captureOrdinal }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(stage, forKey: .stage)
            try values.encode(message, forKey: .message)
            try values.encode(captureOrdinal, forKey: .captureOrdinal)
        }
    }

    struct State: Encodable {
        var status = "in-progress"
        var phase = "precondition"
        var initialApplication: MaterialDiagnosticMetadata.Application?
        var restorationRequired = false
        var accessoryTransition: PolicyChange?
        var restoration: PolicyChange?
        var completedAttemptCount = 0
        var failures: [Failure] = []
        var additionalFailureCount = 0

        var nextCaptureOrdinal: Int? {
            completedAttemptCount < 24 ? completedAttemptCount + 1 : nil
        }

        private enum CodingKeys: String, CodingKey {
            case status, phase, initialApplication, restorationRequired, accessoryTransition, restoration
            case completedAttemptCount, nextCaptureOrdinal, failures, additionalFailureCount
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(status, forKey: .status)
            try values.encode(phase, forKey: .phase)
            try values.encode(initialApplication, forKey: .initialApplication)
            try values.encode(restorationRequired, forKey: .restorationRequired)
            try values.encode(accessoryTransition, forKey: .accessoryTransition)
            try values.encode(restoration, forKey: .restoration)
            try values.encode(completedAttemptCount, forKey: .completedAttemptCount)
            try values.encode(nextCaptureOrdinal, forKey: .nextCaptureOrdinal)
            try values.encode(failures, forKey: .failures)
            try values.encode(additionalFailureCount, forKey: .additionalFailureCount)
        }
    }

    private(set) var state = State()

    func recordFailure(stage: String, message: String, captureOrdinal: Int? = nil) {
        state.status = "failed"
        if state.failures.count < 8 {
            state.failures.append(
                Failure(stage: stage, message: String(message.prefix(1024)), captureOrdinal: captureOrdinal))
        } else {
            state.additionalFailureCount += 1
        }
    }

    func skipAfterCanonicalFailure() {
        recordFailure(stage: "canonical-capture", message: "The canonical capture did not complete operationally.")
        state.phase = "finished"
    }

    func run(
        application: @MainActor () -> MaterialDiagnosticMetadata.Application,
        setPolicy: @MainActor (Policy) -> Bool,
        perform: @MainActor (MaterialDiagnosticHostingPlan.Attempt) async throws -> Void,
        checkpoint: @MainActor () throws -> Void
    ) async {
        state.initialApplication = application()
        guard let initial = state.initialApplication,
            initial.activationPolicy == Policy.prohibited.rawValue, !initial.isActive
        else {
            recordFailure(stage: "precondition", message: "The initial application is not inactive and prohibited.")
            finish(checkpoint: checkpoint)
            return
        }
        await withAccessoryPolicy(
            application: application, setPolicy: setPolicy, perform: perform, checkpoint: checkpoint)
        finish(checkpoint: checkpoint)
    }

    private func withAccessoryPolicy(
        application: @MainActor () -> MaterialDiagnosticMetadata.Application,
        setPolicy: @MainActor (Policy) -> Bool,
        perform: @MainActor (MaterialDiagnosticHostingPlan.Attempt) async throws -> Void,
        checkpoint: @MainActor () throws -> Void
    ) async {
        state.phase = "accessory-transition"
        state.restorationRequired = true
        var activeCaptureOrdinal: Int?
        defer {
            state.phase = "restoration"
            let result = setPolicy(.prohibited)
            let observed = application()
            state.restoration = PolicyChange(
                requestedPolicy: Policy.prohibited.rawValue, returnedSuccess: result, observedApplication: observed)
            if !result || observed.activationPolicy != Policy.prohibited.rawValue || observed.isActive {
                recordFailure(stage: "restoration", message: "The saved inactive/prohibited policy was not restored.")
            }
        }
        do {
            // This checkpoint precedes even the policy change, so a terminated
            // process never leaves evidence claiming restoration already happened.
            try checkpoint()
            let result = setPolicy(.accessory)
            let observed = application()
            state.accessoryTransition = PolicyChange(
                requestedPolicy: Policy.accessory.rawValue, returnedSuccess: result, observedApplication: observed)
            try checkpoint()
            guard result, observed.activationPolicy == Policy.accessory.rawValue, !observed.isActive else {
                recordFailure(
                    stage: "accessory-transition", message: "Accessory policy was rejected or not observed inactive.")
                return
            }
            state.phase = "captures"
            for attempt in MaterialDiagnosticHostingPlan.attempts {
                activeCaptureOrdinal = attempt.ordinal
                try await perform(attempt)
                state.completedAttemptCount += 1
                try checkpoint()
                activeCaptureOrdinal = nil
            }
        } catch {
            // Record the primary failure before the outer defer attempts policy
            // restoration. Cleanup failures cannot replace or precede it.
            recordFailure(
                stage: "capture-or-checkpoint", message: String(describing: error),
                captureOrdinal: activeCaptureOrdinal)
        }
    }

    private func finish(checkpoint: @MainActor () throws -> Void) {
        if state.failures.isEmpty && state.additionalFailureCount == 0 && state.completedAttemptCount == 24 {
            state.status = "completed"
        } else {
            state.status = "failed"
        }
        state.phase = "finished"
        do {
            try checkpoint()
        } catch {
            recordFailure(stage: "final-checkpoint", message: String(describing: error))
        }
    }
}
