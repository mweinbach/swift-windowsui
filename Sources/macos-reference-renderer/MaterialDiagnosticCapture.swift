#if os(macOS)
    import AppKit
    import CryptoKit
    import Foundation
    import SwiftUI

    /// Public SwiftUI drawing only; no native visual-effect wrappers or private
    /// renderer calls. The wallpaper stays outside each isolated panel.
    @MainActor
    private struct MaterialDiagnosticFixture: View {
        let fixture: MaterialDiagnosticPlan.Fixture
        let environmentRecorder: MaterialDiagnosticEnvironmentRecorder
        private let plan = MaterialDiagnosticPlan.self

        var body: some View {
            MaterialDiagnosticEnvironmentProbe(recorder: environmentRecorder, content: content)
                .environment(\.colorScheme, .light)
                .environment(\.displayScale, CGFloat(plan.scale))
        }

        private var content: some View {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(0..<plan.width / plan.stripeWidth, id: \.self) { index in
                            gray(index.isMultiple(of: 2) ? 0.1 : 0.9)
                                .frame(width: CGFloat(plan.stripeWidth))
                        }
                    }
                    .frame(height: CGFloat(plan.bandBoundary))
                    HStack(spacing: 0) {
                        gray(0.1)
                        gray(0.9)
                    }
                    .frame(height: CGFloat(plan.height - plan.bandBoundary))
                }
                panel
                    .frame(width: CGFloat(plan.panel.width), height: CGFloat(plan.panel.height))
                    .offset(x: CGFloat(plan.panel.x), y: CGFloat(plan.panel.y))
            }
            .frame(width: CGFloat(plan.width), height: CGFloat(plan.height))
        }

        private func gray(_ value: Double) -> Color {
            Color(.sRGB, red: value, green: value, blue: value, opacity: 1)
        }

        private var materialPanel: some View {
            ZStack {
                Color.clear
                    .frame(width: CGFloat(plan.panel.width), height: CGFloat(plan.panel.height))
                    .background(.regularMaterial)
            }
        }

        @ViewBuilder private var panel: some View {
            switch fixture {
            case .pattern: Color.clear
            case .tint: Color.white.opacity(0.4)
            case .direct: materialPanel
            case .compositingGroup: materialPanel.compositingGroup()
            case .drawingGroup: materialPanel.drawingGroup(opaque: false, colorMode: .nonLinear)
            case .contentBlur: materialPanel.blur(radius: 3, opaque: false)
            }
        }
    }

    @MainActor
    private final class MaterialDiagnosticEnvironmentRecorder {
        private(set) var observation = MaterialDiagnosticMetadata.EnvironmentObservation()

        func record(_ values: MaterialDiagnosticMetadata.EnvironmentValues) {
            observation.record(values, timestampUTC: materialDiagnosticTimestampUTC())
        }
    }

    /// A transparent observer inside the existing fixture environment. Its
    /// recorder is not observable state and never requests layout or display.
    @MainActor
    private struct MaterialDiagnosticEnvironmentProbe<Content: View>: View {
        let recorder: MaterialDiagnosticEnvironmentRecorder
        let content: Content
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.colorSchemeContrast) private var colorSchemeContrast
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            recorder.record(
                MaterialDiagnosticMetadata.EnvironmentValues(
                    reduceTransparency: reduceTransparency, reduceMotion: reduceMotion,
                    colorScheme: colorSchemeName, colorSchemeContrast: contrastName,
                    displayScale: Double(displayScale)))
            return content
        }

        private var colorSchemeName: String {
            switch colorScheme {
            case .light: return "light"
            case .dark: return "dark"
            @unknown default: return "unknown"
            }
        }

        private var contrastName: String {
            switch colorSchemeContrast {
            case .standard: return "standard"
            case .increased: return "increased"
            @unknown default: return "unknown"
            }
        }
    }

    private func materialDiagnosticTimestampUTC() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    @MainActor
    enum MaterialDiagnosticCapture {
        private struct BitmapDescription: Codable {
            let pixelWidth: Int
            let pixelHeight: Int
            let bitsPerSample: Int
            let samplesPerPixel: Int
            let hasAlpha: Bool
            let bytesPerRow: Int
            let colorSpaceName: String
        }

        private struct Capture: Encodable {
            let repetition: Int
            let timestampUTC: String
            let pngFile: String?
            let sha256: String?
            let decodedPNG: BitmapDescription?
            let measurements: MaterialDiagnosticMeasurements?
            let error: String?
            let captureProvenance: MaterialDiagnosticMetadata.Capture
        }

        private struct Observation: Encodable {
            let fixture: MaterialDiagnosticPlan.Fixture
            let modifierOrder: String
            let captures: [Capture]
            let repeatedMeasurementsStable: Bool
            let effectiveAppearance: String
            let hostIsFlipped: Bool
        }

        private struct Manifest: Encodable {
            let schemaVersion = 1
            let fixtureVersion = MaterialDiagnosticPlan.version
            let qualification = "candidate-only; not pinned SDK qualification or SwiftUI conformance"
            let groupBehaviorReview = "unreviewed; even a passing direct control does not qualify every wrapper"
            let captureAPI = "NSHostingView.cacheDisplay(in:to:), unattached view; no desktop or window capture"
            let pixelCoordinates = "PNG top row first; no automatic orientation correction"
            let logicalWidth = MaterialDiagnosticPlan.width
            let logicalHeight = MaterialDiagnosticPlan.height
            let requestedScale = MaterialDiagnosticPlan.scale
            let requestedAppearance = "light / NSAppearance.aqua"
            let outputColorSpace = "sRGB, converted before PNG encoding; metrics read the decoded PNG"
            let material = "regularMaterial"
            let stripeWidthPoints = MaterialDiagnosticPlan.stripeWidth
            let patternBandBoundaryPoints = MaterialDiagnosticPlan.bandBoundary
            let baselinePhaseSampleInsetPixels = MaterialDiagnosticPlan.stripeEdgeInsetPixels
            let patternDarkSRGB = 0.1
            let patternLightSRGB = 0.9
            let panel = MaterialDiagnosticPlan.panel
            let fineSample = MaterialDiagnosticPlan.fineSample
            let darkSample = MaterialDiagnosticPlan.darkSample
            let lightSample = MaterialDiagnosticPlan.lightSample
            let metric =
                "fine: twice the standard deviation of all fine-region pixels; coarse: absolute patch-mean difference; encoded sRGB luma 0.2126R+0.7152G+0.0722B"
            let thresholds = MaterialDiagnosticThresholds()
            let repetitions = MaterialDiagnosticPlan.repetitions
            let settlingMillisecondsBeforeEachCapture = MaterialDiagnosticPlan.settlingMilliseconds
            let provenance: [String: String]
            let systemAccessibilityScope =
                "sampled once after all captures; per-capture before/after values are in captureProvenance"
            let systemAccessibility: [String: Bool]
            let controlsByRepetition: [MaterialDiagnosticControlResult]
            let positiveControlStatus: String
            let inconclusiveReasons: [String]
            let observations: [Observation]
        }

        /// Operational failures are nonzero exits. A successfully written but
        /// inconclusive capture is not a CI failure and never claims parity.
        static func run(outputRoot: URL, hostingContextExperiment: Bool = false) async throws -> Bool {
            let output = outputRoot.appendingPathComponent("material-diagnostics")
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            _ = NSApplication.shared
            _ = NSApp.setActivationPolicy(.prohibited)
            var observations: [Observation] = []
            for fixture in MaterialDiagnosticPlan.Fixture.allCases {
                let environmentRecorder = MaterialDiagnosticEnvironmentRecorder()
                let host = NSHostingView(
                    rootView: MaterialDiagnosticFixture(fixture: fixture, environmentRecorder: environmentRecorder))
                host.frame = NSRect(
                    x: 0, y: 0,
                    width: CGFloat(MaterialDiagnosticPlan.width), height: CGFloat(MaterialDiagnosticPlan.height))
                host.appearance = NSAppearance(named: .aqua)
                var captures: [Capture] = []
                for repetition in 1...MaterialDiagnosticPlan.repetitions {
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(MaterialDiagnosticPlan.settlingMilliseconds))
                    host.layoutSubtreeIfNeeded()
                    captures.append(
                        capture(
                            host, environmentRecorder: environmentRecorder,
                            fixture: fixture, repetition: repetition, output: output))
                }
                let measured = captures.compactMap(\.measurements)
                observations.append(
                    Observation(
                        fixture: fixture, modifierOrder: modifierOrder(fixture), captures: captures,
                        repeatedMeasurementsStable: measured.count == 2
                            && MaterialDiagnosticAnalysis.areStable(measured[0], measured[1]),
                        effectiveAppearance: host.effectiveAppearance.name.rawValue, hostIsFlipped: host.isFlipped))
            }
            let measurements = (0..<MaterialDiagnosticPlan.repetitions).map { index in
                Dictionary(
                    uniqueKeysWithValues: observations.compactMap { observation in
                        observation.captures[index].measurements.map { (observation.fixture, $0) }
                    })
            }
            let controls = MaterialDiagnosticAnalysis.evaluateRepeatedControls(measurements)
            let manifest = Manifest(
                provenance: provenance(),
                systemAccessibility: [
                    "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                    "increaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                    "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                ],
                controlsByRepetition: controls.repetitions,
                positiveControlStatus: controls.status.rawValue,
                inconclusiveReasons: controls.reasons, observations: observations)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let path = output.appendingPathComponent("manifest.json")
            try encoder.encode(manifest).write(to: path, options: .atomic)
            print("Material positive control: \(manifest.positiveControlStatus); candidate observations only.")
            print("wrote \(path.path)")
            let canonicalSucceeded = !observations.contains { $0.captures.contains { $0.error != nil } }
            if hostingContextExperiment {
                return try await runHostingExperiment(
                    output: output, canonicalManifest: manifest, canonicalManifestPath: path,
                    canonicalSucceeded: canonicalSucceeded)
            }
            return canonicalSucceeded
        }

        private static func capture<V: View>(
            _ host: NSHostingView<V>, environmentRecorder: MaterialDiagnosticEnvironmentRecorder,
            fixture: MaterialDiagnosticPlan.Fixture, repetition: Int, output: URL,
            hostingArm: MaterialDiagnosticHostingPlan.Arm? = nil
        ) -> Capture {
            let before = captureSnapshot(host, environmentRecorder: environmentRecorder)
            var cacheDisplayCompleted = false
            var pngFile: String?
            var hash: String?
            var description: BitmapDescription?
            var measurements: MaterialDiagnosticMeasurements?
            var failure: String?
            do {
                let plan = MaterialDiagnosticPlan.self
                guard
                    let bitmap = NSBitmapImageRep(
                        bitmapDataPlanes: nil, pixelsWide: plan.width * plan.scale,
                        pixelsHigh: plan.height * plan.scale,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 32),
                    let storage = bitmap.bitmapData
                else { throw captureError("Could not allocate the explicit 2x RGBA bitmap.") }
                storage.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                bitmap.size = NSSize(width: CGFloat(plan.width), height: CGFloat(plan.height))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                cacheDisplayCompleted = true
                guard let converted = bitmap.converting(to: .sRGB, renderingIntent: .default),
                    let png = converted.representation(using: .png, properties: [:])
                else { throw captureError("Could not convert the captured bitmap to sRGB and encode PNG.") }
                let name: String
                if let hostingArm {
                    name = "\(hostingArm.rawValue)-\(fixture.rawValue)-\(repetition).png"
                } else {
                    name = "\(fixture.rawValue)-\(repetition).png"
                }
                try png.write(to: output.appendingPathComponent(name), options: .atomic)
                pngFile = name
                hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                guard let decoded = NSBitmapImageRep(data: png) else {
                    throw captureError("Could not decode the written PNG for measurement.")
                }
                description = BitmapDescription(
                    pixelWidth: decoded.pixelsWide, pixelHeight: decoded.pixelsHigh,
                    bitsPerSample: decoded.bitsPerSample, samplesPerPixel: decoded.samplesPerPixel,
                    hasAlpha: decoded.hasAlpha, bytesPerRow: decoded.bytesPerRow,
                    colorSpaceName: decoded.colorSpaceName.rawValue)
                guard !decoded.isPlanar, decoded.bitsPerSample == 8, decoded.samplesPerPixel >= 3 else {
                    throw captureError("Decoded PNG does not have the expected interleaved 8-bit RGB format.")
                }
                measurements = try MaterialDiagnosticAnalysis.measure(
                    width: decoded.pixelsWide, height: decoded.pixelsHigh,
                    pixel: { x, y in
                        guard let color = decoded.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
                        return MaterialDiagnosticPixel(
                            red: Double(color.redComponent), green: Double(color.greenComponent),
                            blue: Double(color.blueComponent), alpha: Double(color.alphaComponent))
                    })
            } catch {
                failure = String(describing: error)
            }
            let after = captureSnapshot(host, environmentRecorder: environmentRecorder)
            // Inspect the public factory's recommendation without using it to
            // change the fixed 2x bitmap or to perform a second render.
            let recommendedBitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds).map(bitmapMetadata)
            return Capture(
                repetition: repetition, timestampUTC: ISO8601DateFormatter().string(from: Date()),
                pngFile: pngFile, sha256: hash, decodedPNG: description, measurements: measurements, error: failure,
                captureProvenance: MaterialDiagnosticMetadata.Capture(
                    before: before, after: after, cacheDisplayCompleted: cacheDisplayCompleted,
                    recommendedBitmap: MaterialDiagnosticMetadata.BitmapRecommendation(bitmap: recommendedBitmap)))
        }

        /// New sidecar fields encode unknown values as null. The original
        /// canonical Capture/Manifest encoding is deliberately untouched.
        private struct RecordedOptional<Value: Encodable>: Encodable {
            var value: Value?

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                if let value {
                    try container.encode(value)
                } else {
                    try container.encodeNil()
                }
            }
        }

        private struct HostingCleanup: Encodable {
            let ownsWindow: Bool
            var status: String
            var closeCalled = false
            var contentDetached = RecordedOptional<Bool>(value: nil)
            var hostHasWindowAfterCleanup = RecordedOptional<Bool>(value: nil)
            var windowAfterCleanup = RecordedOptional<MaterialDiagnosticMetadata.Window>(value: nil)
            var applicationAfterCleanup = RecordedOptional<MaterialDiagnosticMetadata.Application>(value: nil)

            var isValid: Bool {
                guard let application = applicationAfterCleanup.value,
                    application.activationPolicy == "accessory", !application.isActive
                else { return false }
                if !ownsWindow { return status == "not-required" && !closeCalled }
                guard status == "observed", closeCalled, contentDetached.value == true,
                    hostHasWindowAfterCleanup.value == false, let window = windowAfterCleanup.value
                else { return false }
                return !window.isVisible && !window.isKeyWindow && !window.isMainWindow
            }
        }

        private struct HostingAttempt: Encodable {
            let attempt: MaterialDiagnosticHostingPlan.Attempt
            var setup = RecordedOptional<MaterialDiagnosticMetadata.Snapshot>(value: nil)
            var capture = RecordedOptional<Capture>(value: nil)
            var cleanup: HostingCleanup
            var protocolFailures: [String] = []
            var error = RecordedOptional<String>(value: nil)
        }

        private final class HostingAttemptRecorder {
            var value: HostingAttempt

            init(_ attempt: MaterialDiagnosticHostingPlan.Attempt) {
                let ownsWindow = attempt.arm == .unshownWindow
                value = HostingAttempt(
                    attempt: attempt,
                    cleanup: HostingCleanup(ownsWindow: ownsWindow, status: ownsWindow ? "pending" : "not-required"))
            }
        }

        private struct HostingObservation: Encodable {
            let fixture: MaterialDiagnosticPlan.Fixture
            let modifierOrder: String
            let captureOrdinals: [Int]
            let repeatedMeasurementsStable: Bool
        }

        private struct HostingArm: Encodable {
            let arm: MaterialDiagnosticHostingPlan.Arm
            let observations: [HostingObservation]
            let controlsByRepetition: [MaterialDiagnosticControlResult]
            let positiveControlStatus: String
            let inconclusiveReasons: [String]
        }

        private struct HostingSidecar: Encodable {
            let schemaVersion = 1
            let experimentPlanVersion = MaterialDiagnosticHostingPlan.version
            let fixtureVersion = MaterialDiagnosticPlan.version
            let evidenceKind = "material-hosting-context-experiment-candidate"
            let requested = true
            let qualification = MaterialDiagnosticHostingPlan.Qualification()
            let captureAPI = "NSHostingView.cacheDisplay(in:to:); no desktop or window capture"
            let canonicalManifestFile = "manifest.json"
            let canonicalManifestSha256: String
            let canonicalPositiveControlStatus: String
            let canonicalCaptureCount = MaterialDiagnosticHostingPlan.canonicalCaptureCount
            let provenance: [String: String]
            let parameters = MaterialDiagnosticHostingPlan.Parameters()
            let startedAtUTC: String
            let checkpointAtUTC: String
            let finishedAtUTC: RecordedOptional<String>
            let scheduledAttempts = MaterialDiagnosticHostingPlan.attempts
            let attempts: [HostingAttempt]
            let arms: [HostingArm]
            let session: MaterialDiagnosticHostingSession.State
        }

        private static func runHostingExperiment(
            output: URL, canonicalManifest: Manifest, canonicalManifestPath: URL, canonicalSucceeded: Bool
        ) async throws -> Bool {
            let canonicalData = try Data(contentsOf: canonicalManifestPath)
            let canonicalHash = SHA256.hash(data: canonicalData).map { String(format: "%02x", $0) }.joined()
            let started = materialDiagnosticTimestampUTC()
            var finished: String?
            let session = MaterialDiagnosticHostingSession()
            var recorders: [HostingAttemptRecorder] = []
            let path = output.appendingPathComponent(MaterialDiagnosticHostingPlan.fileName)

            func checkpoint() throws {
                if session.state.phase == "finished" && finished == nil {
                    finished = materialDiagnosticTimestampUTC()
                }
                let attempts = recorders.map(\.value)
                let sidecar = HostingSidecar(
                    canonicalManifestSha256: canonicalHash,
                    canonicalPositiveControlStatus: canonicalManifest.positiveControlStatus,
                    provenance: canonicalManifest.provenance, startedAtUTC: started,
                    checkpointAtUTC: materialDiagnosticTimestampUTC(),
                    finishedAtUTC: RecordedOptional(value: finished), attempts: attempts,
                    arms: hostingArms(attempts), session: session.state)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(sidecar).write(to: path, options: .atomic)
            }

            guard canonicalSucceeded else {
                session.skipAfterCanonicalFailure()
                try checkpoint()
                return false
            }
            await session.run(
                application: hostingApplication,
                setPolicy: { policy in
                    switch policy {
                    case .accessory: return NSApp.setActivationPolicy(.accessory)
                    case .prohibited: return NSApp.setActivationPolicy(.prohibited)
                    }
                },
                perform: { attempt in
                    let recorder = HostingAttemptRecorder(attempt)
                    recorders.append(recorder)
                    // Preserve the pending attempt before constructing a host
                    // or window. A forced termination leaves a partial report.
                    try checkpoint()
                    do {
                        try await captureHostingAttempt(recorder, output: output)
                        if !recorder.value.cleanup.isValid || !recorder.value.protocolFailures.isEmpty {
                            throw captureError("The attempt or owned-window cleanup violated the hosting protocol.")
                        }
                    } catch {
                        recorder.value.error.value = String(String(describing: error).prefix(1024))
                        throw error
                    }
                }, checkpoint: checkpoint)
            for failure in session.state.failures {
                FileHandle.standardError.write(
                    Data("Material hosting experiment \(failure.stage): \(failure.message)\n".utf8))
            }
            for arm in hostingArms(recorders.map(\.value)) {
                print("Material hosting \(arm.arm.rawValue): \(arm.positiveControlStatus); candidate capability only.")
            }
            print("Material hosting experiment: \(session.state.status); evidence path: \(path.path)")
            return session.state.status == "completed"
        }

        private static func captureHostingAttempt(_ recorder: HostingAttemptRecorder, output: URL) async throws {
            let attempt = recorder.value.attempt
            let application = hostingApplication()
            guard application.activationPolicy == "accessory", !application.isActive else {
                throw captureError(
                    "Accessory policy and inactivity must be observed before creating experiment objects.")
            }
            let environmentRecorder = MaterialDiagnosticEnvironmentRecorder()
            let host = NSHostingView(
                rootView: MaterialDiagnosticFixture(fixture: attempt.fixture, environmentRecorder: environmentRecorder))
            host.frame = NSRect(
                x: 0, y: 0,
                width: CGFloat(MaterialDiagnosticPlan.width), height: CGFloat(MaterialDiagnosticPlan.height))
            host.appearance = NSAppearance(named: .aqua)
            var ownedWindow: NSWindow?
            defer {
                if let window = ownedWindow {
                    // Local ownership remains strong through settling, capture,
                    // detachment and closure. No ordering or activation call.
                    window.contentView = nil
                    recorder.value.cleanup.contentDetached.value = window.contentView == nil
                    recorder.value.cleanup.hostHasWindowAfterCleanup.value = host.window != nil
                    window.close()
                    recorder.value.cleanup.closeCalled = true
                    recorder.value.cleanup.windowAfterCleanup.value = hostingWindow(window)
                    recorder.value.cleanup.status = "observed"
                }
                // Sample before the enclosing policy restoration can conceal a
                // change in activity or policy during owned-window cleanup.
                recorder.value.cleanup.applicationAfterCleanup.value = hostingApplication()
                if !recorder.value.cleanup.isValid {
                    recorder.value.protocolFailures.append("Cleanup or the inactive accessory policy was not observed.")
                }
            }
            if attempt.arm == .unshownWindow {
                let window = NSWindow(
                    contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                ownedWindow = window
                window.isReleasedWhenClosed = false
                window.contentView = host
                if host.window !== window {
                    recorder.value.protocolFailures.append("The host is not attached to its owned experiment window.")
                }
            }
            recorder.value.setup.value = captureSnapshot(host, environmentRecorder: environmentRecorder)
            if let setup = recorder.value.setup.value {
                recorder.value.protocolFailures += MaterialDiagnosticHostingPlan.protocolFailures(
                    setup, arm: attempt.arm)
            }
            guard recorder.value.protocolFailures.isEmpty else {
                throw captureError("The initial host context violated the hosting protocol.")
            }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(MaterialDiagnosticPlan.settlingMilliseconds))
            host.layoutSubtreeIfNeeded()
            // Refresh the setup observation after settling and guard before
            // calling the same view-cache capture helper as the canonical run.
            let setup = captureSnapshot(host, environmentRecorder: environmentRecorder)
            recorder.value.setup.value = setup
            recorder.value.protocolFailures += MaterialDiagnosticHostingPlan.protocolFailures(setup, arm: attempt.arm)
            if let window = ownedWindow, host.window !== window {
                recorder.value.protocolFailures.append("The host moved away from its owned experiment window.")
            }
            guard recorder.value.protocolFailures.isEmpty else {
                throw captureError("The settled host context violated the hosting protocol.")
            }
            let result = capture(
                host, environmentRecorder: environmentRecorder, fixture: attempt.fixture,
                repetition: attempt.repetition, output: output, hostingArm: attempt.arm)
            recorder.value.capture.value = result
            recorder.value.protocolFailures += MaterialDiagnosticHostingPlan.protocolFailures(
                result.captureProvenance.before, arm: attempt.arm)
            recorder.value.protocolFailures += MaterialDiagnosticHostingPlan.protocolFailures(
                result.captureProvenance.after, arm: attempt.arm)
            if let window = ownedWindow, host.window !== window {
                recorder.value.protocolFailures.append("The host changed window during capture.")
            }
            if let error = result.error { throw captureError(error) }
            guard recorder.value.protocolFailures.isEmpty else {
                throw captureError("The captured host context violated the hosting protocol.")
            }
        }

        private static func hostingArms(_ attempts: [HostingAttempt]) -> [HostingArm] {
            func measurements(_ value: HostingAttempt) -> MaterialDiagnosticMeasurements? {
                guard value.error.value == nil, value.protocolFailures.isEmpty, value.cleanup.isValid,
                    let capture = value.capture.value, capture.error == nil
                else { return nil }
                return capture.measurements
            }
            let samples = attempts.map {
                MaterialDiagnosticHostingPlan.Sample(attempt: $0.attempt, measurements: measurements($0))
            }
            return MaterialDiagnosticHostingPlan.Arm.allCases.map { arm in
                let observations = MaterialDiagnosticPlan.Fixture.allCases.map { fixture in
                    let matching = attempts.filter { $0.attempt.arm == arm && $0.attempt.fixture == fixture }
                    let measured = matching.compactMap(measurements)
                    return HostingObservation(
                        fixture: fixture, modifierOrder: modifierOrder(fixture),
                        captureOrdinals: matching.map { $0.attempt.ordinal },
                        repeatedMeasurementsStable: measured.count == 2
                            && MaterialDiagnosticAnalysis.areStable(measured[0], measured[1]))
                }
                let controls = MaterialDiagnosticHostingPlan.evaluateControls(arm: arm, samples: samples)
                return HostingArm(
                    arm: arm, observations: observations, controlsByRepetition: controls.repetitions,
                    positiveControlStatus: controls.status.rawValue, inconclusiveReasons: controls.reasons)
            }
        }

        private static func hostingApplication() -> MaterialDiagnosticMetadata.Application {
            let policy: String
            switch NSApp.activationPolicy() {
            case .prohibited: policy = "prohibited"
            case .accessory: policy = "accessory"
            case .regular: policy = "regular"
            @unknown default: policy = "unknown"
            }
            return MaterialDiagnosticMetadata.Application(
                activationPolicy: policy, isActive: NSApp.isActive, isHidden: NSApp.isHidden, isRunning: NSApp.isRunning
            )
        }

        private static func hostingWindow(_ window: NSWindow) -> MaterialDiagnosticMetadata.Window {
            MaterialDiagnosticMetadata.Window(
                isVisible: window.isVisible, isMiniaturized: window.isMiniaturized,
                isKeyWindow: window.isKeyWindow, isMainWindow: window.isMainWindow,
                occlusionStateVisible: window.occlusionState.contains(.visible),
                backingScaleFactor: Double(window.backingScaleFactor))
        }

        private static func captureSnapshot<V: View>(
            _ host: NSHostingView<V>, environmentRecorder: MaterialDiagnosticEnvironmentRecorder
        ) -> MaterialDiagnosticMetadata.Snapshot {
            let timestamp = materialDiagnosticTimestampUTC()
            let workspace = NSWorkspace.shared
            let systemAccessibility = MaterialDiagnosticMetadata.SystemAccessibility(
                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
            let window = host.window.map {
                MaterialDiagnosticMetadata.Window(
                    isVisible: $0.isVisible, isMiniaturized: $0.isMiniaturized,
                    isKeyWindow: $0.isKeyWindow, isMainWindow: $0.isMainWindow,
                    occlusionStateVisible: $0.occlusionState.contains(.visible),
                    backingScaleFactor: Double($0.backingScaleFactor))
            }
            let layer = host.layer
            let hostMetadata = MaterialDiagnosticMetadata.Host(
                hasWindow: window != nil, hasSuperview: host.superview != nil,
                isHidden: host.isHidden, isHiddenOrHasHiddenAncestor: host.isHiddenOrHasHiddenAncestor,
                isFlipped: host.isFlipped, effectiveAppearance: host.effectiveAppearance.name.rawValue,
                frame: rectangleMetadata(host.frame), bounds: rectangleMetadata(host.bounds),
                visibleRect: rectangleMetadata(host.visibleRect),
                convertedBackingBounds: rectangleMetadata(host.convertToBacking(host.bounds)),
                wantsLayer: host.wantsLayer, hasLayer: layer != nil,
                layerContentsScale: layer.map { Double($0.contentsScale) }, window: window)
            let policy: String
            switch NSApp.activationPolicy() {
            case .regular: policy = "regular"
            case .accessory: policy = "accessory"
            case .prohibited: policy = "prohibited"
            @unknown default: policy = "unknown"
            }
            return MaterialDiagnosticMetadata.Snapshot(
                timestampUTC: timestamp, systemAccessibility: systemAccessibility,
                swiftUIEnvironment: environmentRecorder.observation,
                application: MaterialDiagnosticMetadata.Application(
                    activationPolicy: policy, isActive: NSApp.isActive,
                    isHidden: NSApp.isHidden, isRunning: NSApp.isRunning),
                host: hostMetadata)
        }

        private static func rectangleMetadata(_ rectangle: NSRect) -> MaterialDiagnosticMetadata.Rectangle {
            MaterialDiagnosticMetadata.Rectangle(
                x: Double(rectangle.origin.x), y: Double(rectangle.origin.y),
                width: Double(rectangle.width), height: Double(rectangle.height))
        }

        private static func bitmapMetadata(_ bitmap: NSBitmapImageRep) -> MaterialDiagnosticMetadata.Bitmap {
            MaterialDiagnosticMetadata.Bitmap(
                pixelWidth: bitmap.pixelsWide, pixelHeight: bitmap.pixelsHigh,
                logicalWidth: Double(bitmap.size.width), logicalHeight: Double(bitmap.size.height),
                bitsPerSample: bitmap.bitsPerSample, samplesPerPixel: bitmap.samplesPerPixel,
                hasAlpha: bitmap.hasAlpha, isPlanar: bitmap.isPlanar,
                bitsPerPixel: bitmap.bitsPerPixel, bytesPerRow: bitmap.bytesPerRow,
                bitmapFormatRawValue: bitmap.bitmapFormat.rawValue,
                colorSpaceName: bitmap.colorSpaceName.rawValue)
        }

        private static func modifierOrder(_ fixture: MaterialDiagnosticPlan.Fixture) -> String {
            let material = "ZStack { Color.clear.frame(width:336,height:240).background(.regularMaterial) }"
            switch fixture {
            case .pattern: return "pattern only"
            case .tint: return "Color.white.opacity(0.4) over pattern"
            case .direct: return material
            case .compositingGroup: return material + ".compositingGroup()"
            case .drawingGroup: return material + ".drawingGroup(opaque:false,colorMode:.nonLinear)"
            case .contentBlur: return material + ".blur(radius:3,opaque:false)"
            }
        }

        private static func captureError(_ message: String) -> NSError {
            NSError(domain: "MaterialDiagnosticCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        private static func provenance() -> [String: String] {
            var values = [
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                "xcodeAtCapture": command("/usr/bin/xcodebuild", ["-version"]),
                "swiftAtCapture": command("/usr/bin/xcrun", ["swift", "--version"]),
                "sdkVersionAtCapture": command("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-version"]),
                "sdkBuildAtCapture": command("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-build-version"]),
                "sdkPathAtCapture": command("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"]),
                "osBuild": command("/usr/bin/sw_vers", ["-buildVersion"]),
                "sourceCommitAtCapture": command("/usr/bin/git", ["rev-parse", "HEAD"]),
                "trackedWorkingTreeAtCapture": command(
                    "/usr/bin/git", ["status", "--porcelain", "--untracked-files=no"]),
                "buildProvenance":
                    "Compiler/source values describe capture-time tools and checkout; not embedded build identity.",
                "declaredBuildConfiguration": ProcessInfo.processInfo.environment[
                    "SWIFT_WINDOWSUI_REFERENCE_BUILD_CONFIGURATION"] ?? "unspecified",
                "executableSHA256": executableHash(),
            ]
            #if swift(>=6.0)
                values["swiftLanguageMode"] = "6"
            #else
                values["swiftLanguageMode"] = "earlier than 6"
            #endif
            #if arch(arm64)
                values["processArchitecture"] = "arm64"
            #elseif arch(x86_64)
                values["processArchitecture"] = "x86_64"
            #else
                values["processArchitecture"] = "other"
            #endif
            for key in ["GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "ImageOS", "ImageVersion"] {
                values[key] = ProcessInfo.processInfo.environment[key] ?? "unavailable"
            }
            return values
        }

        private static func executableHash() -> String {
            do {
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: CommandLine.arguments[0]))
                defer { try? handle.close() }
                var hash = SHA256()
                while let data = try handle.read(upToCount: 65_536), !data.isEmpty { hash.update(data: data) }
                return hash.finalize().map { String(format: "%02x", $0) }.joined()
            } catch {
                return "unavailable: \(error)"
            }
        }

        private static func command(_ executable: String, _ arguments: [String]) -> String {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                return process.terminationStatus == 0
                    ? text : "unavailable (exit \(process.terminationStatus)): \(text)"
            } catch {
                return "unavailable: \(error)"
            }
        }
    }
#endif
