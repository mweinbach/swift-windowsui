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
        static func run(outputRoot: URL) async throws -> Bool {
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
            return !observations.contains { $0.captures.contains { $0.error != nil } }
        }

        private static func capture<V: View>(
            _ host: NSHostingView<V>, environmentRecorder: MaterialDiagnosticEnvironmentRecorder,
            fixture: MaterialDiagnosticPlan.Fixture, repetition: Int, output: URL
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
                let name = "\(fixture.rawValue)-\(repetition).png"
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
