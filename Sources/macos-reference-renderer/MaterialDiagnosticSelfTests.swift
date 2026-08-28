import Foundation

/// Portable classifier and metadata checks. These synthetic values are never
/// native observations and cannot establish what SwiftUI renders on macOS.
enum MaterialDiagnosticSelfTests {
    @MainActor
    static func run() async throws -> Int {
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
        count += try await runHostingChecks(
            pattern: pattern, tint: tint, filtered: filtered, opaque: measure(fine: 0, coarse: 0))
        return count
    }

    @MainActor
    private static func runHostingChecks(
        pattern: MaterialDiagnosticMeasurements, tint: MaterialDiagnosticMeasurements,
        filtered: MaterialDiagnosticMeasurements, opaque: MaterialDiagnosticMeasurements
    ) async throws -> Int {
        typealias Plan = MaterialDiagnosticHostingPlan
        typealias Metadata = MaterialDiagnosticMetadata
        var count = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else {
                throw NSError(
                    domain: "MaterialDiagnosticSelfTests", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: name])
            }
            count += 1
        }
        func object(_ value: some Encodable) throws -> [String: Any] {
            guard let result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
            else {
                throw NSError(domain: "MaterialDiagnosticSelfTests", code: 4)
            }
            return result
        }

        let attempts = Plan.attempts
        let fixtureOrder: [MaterialDiagnosticPlan.Fixture] = [
            .pattern, .tint, .direct, .compositingGroup, .drawingGroup, .contentBlur,
        ]
        try check(
            Plan.version == 1 && Plan.fileName == "hosting-experiment.json" && Plan.canonicalCaptureCount == 12,
            "The optional hosting experiment does not replace the canonical twelve captures")
        try check(MaterialDiagnosticPlan.Fixture.allCases == fixtureOrder, "Hosting fixture order remains predeclared")
        try check(
            Plan.Arm.allCases.map(\.rawValue) == ["accessory-unattached", "accessory-unshown-window"],
            "The hosting experiment has exactly its two approved arms")
        try check(attempts.count == 24, "The hosting schedule contains exactly twenty-four attempts")
        try check(attempts.map(\.ordinal) == Array(1...24), "Capture ordinals are exact and contiguous")
        try check(
            attempts.map(\.pairIndex) == [
                1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
            ],
            "Adjacent attempts retain the predeclared pair indices")
        try check(
            attempts.enumerated().allSatisfy { $0.element.positionInPair == $0.offset % 2 + 1 },
            "Each scheduled pair has positions one and two")
        let identities = attempts.map { attempt in
            "\(attempt.arm == .unattached ? "U" : "W"):\(attempt.fixture.rawValue):\(attempt.repetition)"
        }
        let expectedIdentities = [
            "U:pattern-control:1", "W:pattern-control:1", "W:pattern-control:2", "U:pattern-control:2",
            "U:flat-tint-control:1", "W:flat-tint-control:1", "W:flat-tint-control:2", "U:flat-tint-control:2",
            "U:material-direct-control:1", "W:material-direct-control:1", "W:material-direct-control:2",
            "U:material-direct-control:2",
            "U:material-compositing-group:1", "W:material-compositing-group:1", "W:material-compositing-group:2",
            "U:material-compositing-group:2",
            "U:material-drawing-group:1", "W:material-drawing-group:1", "W:material-drawing-group:2",
            "U:material-drawing-group:2",
            "U:material-content-blur:1", "W:material-content-blur:1", "W:material-content-blur:2",
            "U:material-content-blur:2",
        ]
        try check(
            identities == expectedIdentities, "Each fixture counterbalances U/W then W/U without pooling repetitions")
        try check(Set(identities).count == 24, "Every scheduled arm/fixture/repetition identity is distinct")
        try check(Set(attempts.map(\.pngFile)).count == 24, "Every scheduled attempt has a distinct PNG filename")
        try check(
            attempts.allSatisfy { $0.pngFile == "\($0.arm.rawValue)-\($0.fixture.rawValue)-\($0.repetition).png" },
            "Hosting filenames preserve arm, fixture, and repetition without canonical filename collisions")
        try check(Plan.attempts == attempts, "Reading the schedule again does not advance or mutate attempt identities")
        for arm in Plan.Arm.allCases {
            let selected = attempts.filter { $0.arm == arm }
            try check(
                selected.count == 12 && selected.filter { $0.positionInPair == 1 }.count == 6
                    && selected.filter { $0.positionInPair == 2 }.count == 6,
                "Each arm has twelve fresh scheduled attempts and balanced pair positions")
            try check(
                fixtureOrder.allSatisfy { fixture in
                    Set(selected.filter { $0.fixture == fixture }.map(\.repetition)) == Set([1, 2])
                }, "Each arm has both repetitions for every fixture")
        }
        let firstAttemptJSON = try object(attempts[0])
        let lastAttemptJSON = try object(attempts[23])
        try check(
            firstAttemptJSON["ordinal"] as? Int == 1 && firstAttemptJSON["pairIndex"] as? Int == 1
                && firstAttemptJSON["pngFile"] as? String == "accessory-unattached-pattern-control-1.png"
                && lastAttemptJSON["ordinal"] as? Int == 24 && lastAttemptJSON["pairIndex"] as? Int == 12
                && lastAttemptJSON["pngFile"] as? String == "accessory-unattached-material-content-blur-2.png",
            "Encoded attempts retain explicit ordinal, pair, and PNG identities")
        let parameters = Plan.Parameters()
        try check(
            parameters.logicalWidth == 384 && parameters.logicalHeight == 288 && parameters.requestedScale == 2
                && parameters.repetitions == 2 && parameters.settlingMillisecondsBeforeEachCapture == 50,
            "The hosting protocol retains the approved extent, scale, repetitions, and settling interval")
        let qualification = Plan.Qualification()
        try check(
            !qualification.nativeBehaviorReviewed && !qualification.nativeRuntimeBuildReviewed
                && !qualification.releaseQualified,
            "Synthetic hosting checks do not qualify native behavior, a runtime build, or a release")

        func window(visible: Bool = false, key: Bool = false, main: Bool = false) -> Metadata.Window {
            Metadata.Window(
                isVisible: visible, isMiniaturized: false, isKeyWindow: key, isMainWindow: main,
                occlusionStateVisible: true, backingScaleFactor: 1)
        }
        func observedEnvironment(colorScheme: String = "light", displayScale: Double = 2)
            -> Metadata.EnvironmentObservation
        {
            var result = Metadata.EnvironmentObservation()
            result.record(
                Metadata.EnvironmentValues(
                    reduceTransparency: true, reduceMotion: true, colorScheme: colorScheme,
                    colorSchemeContrast: "increased", displayScale: displayScale),
                timestampUTC: "synthetic-hosting-environment")
            return result
        }
        let extent = Metadata.Rectangle(x: 0, y: 0, width: 384, height: 288)
        func snapshot(
            policy: String = "accessory", active: Bool = false,
            hasWindow: Bool = false, hasSuperview: Bool = false, ownedWindow: Metadata.Window? = nil,
            frame: Metadata.Rectangle? = nil, bounds: Metadata.Rectangle? = nil,
            flipped: Bool = true, appearance: String = "NSAppearanceNameAqua",
            environment: Metadata.EnvironmentObservation = .init()
        ) -> Metadata.Snapshot {
            Metadata.Snapshot(
                timestampUTC: "synthetic-hosting-snapshot",
                systemAccessibility: Metadata.SystemAccessibility(
                    reduceTransparency: true, increaseContrast: true, reduceMotion: true),
                swiftUIEnvironment: environment,
                application: Metadata.Application(
                    activationPolicy: policy, isActive: active, isHidden: false, isRunning: false),
                host: Metadata.Host(
                    hasWindow: hasWindow, hasSuperview: hasSuperview, isHidden: false,
                    isHiddenOrHasHiddenAncestor: false,
                    isFlipped: flipped, effectiveAppearance: appearance, frame: frame ?? extent,
                    bounds: bounds ?? extent,
                    visibleRect: extent, convertedBackingBounds: extent, wantsLayer: false, hasLayer: false,
                    layerContentsScale: nil, window: ownedWindow))
        }
        try check(
            Plan.protocolFailures(snapshot(), arm: .unattached).isEmpty,
            "A valid unattached synthetic host satisfies the protocol")
        try check(
            Plan.protocolFailures(
                snapshot(
                    hasWindow: true, hasSuperview: true, ownedWindow: window(), environment: observedEnvironment()),
                arm: .unshownWindow
            ).isEmpty,
            "Backing scale, occlusion, accessibility, and body observations are recorded without imposing extra conditions"
        )
        try check(
            Plan.protocolFailures(snapshot(policy: "prohibited"), arm: .unattached).count == 1,
            "Observed activation policy must be accessory")
        try check(
            Plan.protocolFailures(snapshot(active: true), arm: .unattached).count == 1,
            "An active application fails the protocol")
        for invalid in [
            Metadata.Rectangle(x: 1, y: 0, width: 384, height: 288),
            Metadata.Rectangle(x: 0, y: 1, width: 384, height: 288),
            Metadata.Rectangle(x: 0, y: 0, width: 383, height: 288),
            Metadata.Rectangle(x: 0, y: 0, width: 384, height: 287),
        ] {
            try check(
                Plan.protocolFailures(snapshot(frame: invalid), arm: .unattached).count == 1,
                "Every frame coordinate is checked")
            try check(
                Plan.protocolFailures(snapshot(bounds: invalid), arm: .unattached).count == 1,
                "Every bounds coordinate is checked")
        }
        try check(
            Plan.protocolFailures(snapshot(flipped: false), arm: .unattached).count == 1, "Host orientation is fixed")
        try check(
            Plan.protocolFailures(snapshot(appearance: "NSAppearanceNameDarkAqua"), arm: .unattached).count == 1,
            "Host appearance is fixed")
        try check(
            Plan.protocolFailures(snapshot(environment: observedEnvironment(colorScheme: "dark")), arm: .unattached)
                .count == 1,
            "An observed SwiftUI color scheme mismatch fails the protocol")
        try check(
            Plan.protocolFailures(snapshot(environment: observedEnvironment(displayScale: 1)), arm: .unattached).count
                == 1,
            "An observed SwiftUI display scale mismatch fails the protocol")
        for invalid in [
            snapshot(hasWindow: true), snapshot(ownedWindow: window()), snapshot(hasSuperview: true),
        ] {
            try check(
                Plan.protocolFailures(invalid, arm: .unattached).count == 1, "Any unattached-arm attachment is rejected"
            )
        }
        for invalid in [snapshot(), snapshot(hasWindow: true), snapshot(ownedWindow: window())] {
            try check(
                Plan.protocolFailures(invalid, arm: .unshownWindow).count == 1,
                "The window arm requires both attachment and window metadata")
        }
        for invalid in [window(visible: true), window(key: true), window(main: true)] {
            try check(
                Plan.protocolFailures(snapshot(hasWindow: true, ownedWindow: invalid), arm: .unshownWindow).count == 1,
                "A visible, key, or main owned window is rejected independently")
        }
        let multipleFailures = Plan.protocolFailures(
            snapshot(
                policy: "prohibited", active: true, hasSuperview: true,
                frame: Metadata.Rectangle(x: 1, y: 0, width: 384, height: 288), flipped: false),
            arm: .unattached)
        try check(
            multipleFailures.count == 5 && Set(multipleFailures).count == 5,
            "Protocol failures accumulate without hiding independent violations")

        func samples(unattached: MaterialDiagnosticMeasurements, window: MaterialDiagnosticMeasurements) -> [Plan
            .Sample]
        {
            attempts.map { attempt in
                let measurements: MaterialDiagnosticMeasurements
                switch attempt.fixture {
                case .pattern: measurements = pattern
                case .tint: measurements = tint
                default: measurements = attempt.arm == .unattached ? unattached : window
                }
                return Plan.Sample(attempt: attempt, measurements: measurements)
            }
        }
        let forward = samples(unattached: filtered, window: opaque)
        let reverse = samples(unattached: opaque, window: filtered)
        try check(
            Plan.evaluateControls(arm: .unattached, samples: forward).status == .confirmed,
            "U positive controls are classified within U")
        try check(
            Plan.evaluateControls(arm: .unshownWindow, samples: forward).status == .inconclusive,
            "W opaque output cannot borrow U's positive controls")
        try check(
            Plan.evaluateControls(arm: .unattached, samples: reverse).status == .inconclusive,
            "U opaque output cannot borrow W's positive controls")
        try check(
            Plan.evaluateControls(arm: .unshownWindow, samples: reverse).status == .confirmed,
            "Reversing arm outcomes preserves independent W classification")
        let positive = samples(unattached: filtered, window: filtered)
        let missing = positive.filter {
            !($0.attempt.arm == .unattached && $0.attempt.fixture == .direct && $0.attempt.repetition == 2)
        }
        try check(
            Plan.evaluateControls(arm: .unattached, samples: missing).status == .inconclusive,
            "Missing U direct capture cannot borrow W's repetition")
        try check(
            Plan.evaluateControls(arm: .unshownWindow, samples: missing).status == .confirmed,
            "A missing U sample does not invalidate complete W controls")
        let unmeasured = positive.map { sample in
            Plan.Sample(
                attempt: sample.attempt,
                measurements: sample.attempt.arm == .unattached && sample.attempt.fixture == .direct
                    && sample.attempt.repetition == 1
                    ? nil : sample.measurements)
        }
        try check(
            Plan.evaluateControls(arm: .unattached, samples: unmeasured).status == .inconclusive,
            "An unmeasured U control remains missing")
        try check(
            Plan.evaluateControls(arm: .unshownWindow, samples: unmeasured).status == .confirmed,
            "An unmeasured U control does not erase W observations")
        let splitRepetitions = positive.filter {
            ($0.attempt.arm == .unattached && $0.attempt.repetition == 1)
                || ($0.attempt.arm == .unshownWindow && $0.attempt.repetition == 2)
        }
        for arm in Plan.Arm.allCases {
            try check(
                Plan.evaluateControls(arm: arm, samples: splitRepetitions).status == .inconclusive,
                "One positive repetition per arm is not two repetitions in either arm")
        }
        let duplicate = positive + [positive[0]]
        try check(
            Plan.evaluateControls(arm: .unattached, samples: duplicate).status == .inconclusive,
            "A duplicate U fixture invalidates that repetition")
        try check(
            Plan.evaluateControls(arm: .unshownWindow, samples: duplicate).status == .confirmed,
            "A duplicate U fixture does not contaminate W")
        let invalidAttempt = Plan.Attempt(
            ordinal: 999, pairIndex: 1, positionInPair: 1, arm: .unattached, fixture: .pattern, repetition: 1)
        let malformed = [Plan.Sample(attempt: invalidAttempt, measurements: pattern)] + Array(positive.dropFirst())
        try check(
            Plan.evaluateControls(arm: .unattached, samples: malformed).status == .inconclusive,
            "An invalid ordinal cannot establish a scheduled U control")
        try check(
            Plan.evaluateControls(arm: .unshownWindow, samples: malformed).status == .confirmed,
            "A malformed U attempt cannot change W's independent result")

        do {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            let initial = driver.application
            await driver.run(session)
            try check(
                session.state.initialApplication == initial, "The session retains its observed initial application")
            try check(
                driver.performed == attempts, "A successful session performs each fresh scheduled attempt exactly once")
            try check(
                driver.policyRequests == ["accessory", "prohibited"],
                "A successful session changes then restores the saved policy once")
            try check(
                session.state.status == "completed" && session.state.phase == "finished"
                    && session.state.completedAttemptCount == 24 && session.state.nextCaptureOrdinal == nil,
                "Successful completion counts all twenty-four attempts and has no next capture")
            try check(
                session.state.restorationRequired && session.state.accessoryTransition?.returnedSuccess == true
                    && session.state.restoration?.returnedSuccess == true && session.state.failures.isEmpty,
                "Successful completion retains actual transition and restoration observations")
            try check(
                driver.checkpoints.count == 27,
                "The session checkpoints before and after policy change, after each capture, and after restoration")
            try check(
                Array(driver.events.prefix(4)) == ["checkpoint-1", "policy-accessory", "checkpoint-2", "capture-1"],
                "Both initial checkpoints precede the first perform callback")
            try check(
                Array(driver.events.suffix(2)) == ["policy-prohibited", "checkpoint-27"],
                "Policy restoration precedes the final checkpoint")
            try check(
                driver.checkpoints.first?.phase == "accessory-transition"
                    && driver.checkpoints.first?.restorationRequired == true
                    && driver.checkpoints.first?.accessoryTransition == nil
                    && driver.checkpoints.first?.restoration == nil,
                "The first checkpoint records pending restoration before any policy mutation")
            try check(
                driver.checkpoints.dropLast().allSatisfy { $0.restoration == nil }
                    && driver.checkpoints.last?.restoration?.observedApplication.activationPolicy == "prohibited"
                    && driver.checkpoints.last?.status == "completed",
                "Only the final checkpoint can claim the observed restoration")
            try check(
                Array(driver.checkpoints.dropFirst(2).prefix(24)).map(\.completedAttemptCount) == Array(1...24),
                "Each successful perform advances the checkpointed completion count once")
            let finalJSON = try object(session.state)
            try check(
                finalJSON["nextCaptureOrdinal"] is NSNull,
                "Finished session JSON encodes the absent next capture explicitly")
        }
        for mode in ["rejected", "wrong-observation", "active-observation"] {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.accessoryReturnedSuccess = mode != "rejected"
            driver.accessoryObservedPolicy = mode == "active-observation" ? "accessory" : "prohibited"
            driver.accessoryObservedActive = mode == "active-observation"
            await driver.run(session)
            try check(
                driver.performed.isEmpty && session.state.completedAttemptCount == 0,
                "An unsuccessful accessory transition never starts captures: \(mode)")
            try check(
                driver.policyRequests == ["accessory", "prohibited"] && session.state.restoration != nil,
                "Every attempted transition is restored: \(mode)")
            try check(
                session.state.status == "failed" && session.state.failures.map(\.stage) == ["accessory-transition"],
                "Transition failure is retained explicitly: \(mode)")
        }
        for initial in [
            Metadata.Application(activationPolicy: "prohibited", isActive: true, isHidden: false, isRunning: false),
            Metadata.Application(activationPolicy: "regular", isActive: false, isHidden: false, isRunning: false),
        ] {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.application = initial
            await driver.run(session)
            try check(
                driver.policyRequests.isEmpty && driver.performed.isEmpty,
                "Invalid initial application state is not mutated")
            try check(
                session.state.failures.map(\.stage) == ["precondition"] && session.state.phase == "finished"
                    && !session.state.restorationRequired && session.state.restoration == nil,
                "Precondition failure cannot fabricate a policy restoration")
            try check(
                driver.checkpoints.count == 1 && driver.checkpoints[0].status == "failed",
                "Precondition failure still checkpoints its failed state")
        }
        do {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.captureFailureOrdinal = 3
            await driver.run(session)
            try check(
                driver.performed.map(\.ordinal) == [1, 2, 3] && session.state.completedAttemptCount == 2,
                "A throwing capture does not advance its completion count or run later captures")
            try check(
                session.state.nextCaptureOrdinal == 3 && session.state.failures.first?.captureOrdinal == 3
                    && session.state.failures.first?.message == "synthetic-capture-3",
                "Capture failure preserves its current ordinal and primary error")
            try check(
                Array(driver.events.suffix(3)) == ["capture-3", "policy-prohibited", "checkpoint-5"],
                "A throwing capture restores policy before its failed final checkpoint")
            try check(
                session.state.status == "failed" && session.state.restoration?.returnedSuccess == true,
                "Restoration does not turn a capture failure into success")
        }
        for checkpoint in [1, 2] {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.checkpointFailures = [checkpoint]
            await driver.run(session)
            try check(
                driver.performed.isEmpty && session.state.completedAttemptCount == 0,
                "An initial checkpoint failure prevents the first capture")
            try check(
                driver.policyRequests == (checkpoint == 1 ? ["prohibited"] : ["accessory", "prohibited"])
                    && session.state.restoration?.returnedSuccess == true,
                "Restoration runs even when the checkpoint precedes the accessory policy request")
            try check(
                session.state.failures.map(\.stage) == ["capture-or-checkpoint"]
                    && session.state.failures.first?.captureOrdinal == nil,
                "A transition checkpoint failure has no fabricated capture ordinal")
            try check(
                Array(driver.events.suffix(2)) == ["policy-prohibited", "checkpoint-\(checkpoint + 1)"],
                "Initial checkpoint failure is followed by restoration and a final checkpoint")
        }
        for completed in [1, 24] {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.checkpointFailures = [completed + 2]
            await driver.run(session)
            try check(
                session.state.completedAttemptCount == completed && driver.performed.count == completed,
                "A post-capture checkpoint failure preserves completed work and stops further captures")
            try check(
                session.state.failures.first?.captureOrdinal == completed
                    && session.state.nextCaptureOrdinal == (completed == 24 ? nil : completed + 1),
                "A post-capture checkpoint failure names the current capture, not the next one")
            try check(
                session.state.status == "failed" && session.state.restoration?.returnedSuccess == true,
                "Even the twenty-fourth capture's checkpoint failure remains failed after restoration")
        }
        for mode in ["false-return", "wrong-policy", "active"] {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.restorationReturnedSuccess = mode != "false-return"
            driver.restorationObservedPolicy = mode == "wrong-policy" ? "accessory" : "prohibited"
            driver.restorationObservedActive = mode == "active"
            await driver.run(session)
            try check(
                session.state.completedAttemptCount == 24 && session.state.nextCaptureOrdinal == nil,
                "Restoration failure does not erase completed capture counts")
            try check(
                session.state.status == "failed" && session.state.failures.map(\.stage) == ["restoration"],
                "Observed restoration failure prevents session success: \(mode)")
            try check(
                driver.checkpoints.last?.status == "failed" && driver.checkpoints.last?.restoration != nil,
                "The final checkpoint includes the failed restoration observation")
        }
        for primary in ["capture", "checkpoint"] {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.restorationReturnedSuccess = false
            if primary == "capture" { driver.captureFailureOrdinal = 1 } else { driver.checkpointFailures = [2] }
            await driver.run(session)
            try check(
                session.state.failures.map(\.stage) == ["capture-or-checkpoint", "restoration"],
                "The primary error precedes and survives restoration failure")
            try check(
                session.state.failures.first?.message
                    == (primary == "capture" ? "synthetic-capture-1" : "synthetic-checkpoint-2")
                    && session.state.completedAttemptCount == 0 && session.state.status == "failed",
                "Both failures retain the original cause and exact completion count")
            try check(
                Array(driver.events.suffix(2)) == ["policy-prohibited", "checkpoint-3"],
                "Both failures still reach the final checkpoint after the restoration attempt")
        }
        do {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.checkpointFailures = [27]
            await driver.run(session)
            try check(
                session.state.completedAttemptCount == 24 && session.state.restoration?.returnedSuccess == true,
                "A final checkpoint error does not erase observed completed work or restoration")
            try check(
                session.state.status == "failed" && session.state.failures.map(\.stage) == ["final-checkpoint"],
                "A final checkpoint write failure prevents completed status")
            try check(
                Array(driver.events.suffix(2)) == ["policy-prohibited", "checkpoint-27"],
                "Final checkpoint failure happens after policy restoration")
        }
        do {
            let session = MaterialDiagnosticHostingSession()
            let driver = MaterialDiagnosticSyntheticHostingDriver()
            driver.captureFailureOrdinal = 2
            driver.restorationReturnedSuccess = false
            driver.checkpointFailures = [4]
            await driver.run(session)
            try check(
                session.state.failures.map(\.stage) == ["capture-or-checkpoint", "restoration", "final-checkpoint"]
                    && session.state.completedAttemptCount == 1 && session.state.additionalFailureCount == 0,
                "Capture, restoration, and final checkpoint errors remain distinct and ordered")
        }
        do {
            let session = MaterialDiagnosticHostingSession()
            session.skipAfterCanonicalFailure()
            try check(
                session.state.status == "failed" && session.state.phase == "finished"
                    && session.state.failures.map(\.stage) == ["canonical-capture"]
                    && session.state.completedAttemptCount == 0 && !session.state.restorationRequired,
                "Canonical failure skips the experiment without claiming a transition or capture")
        }
        return count
    }
}

/// Only injected callback observations are recorded here. Distinct scheduled
/// attempts are not evidence that native hosting objects were freshly allocated.
@MainActor
private final class MaterialDiagnosticSyntheticHostingDriver {
    var application = MaterialDiagnosticMetadata.Application(
        activationPolicy: "prohibited", isActive: false, isHidden: false, isRunning: false)
    var accessoryReturnedSuccess = true
    var accessoryObservedPolicy = "accessory"
    var accessoryObservedActive = false
    var restorationReturnedSuccess = true
    var restorationObservedPolicy = "prohibited"
    var restorationObservedActive = false
    var captureFailureOrdinal: Int?
    var checkpointFailures: Set<Int> = []
    private(set) var policyRequests: [String] = []
    private(set) var performed: [MaterialDiagnosticHostingPlan.Attempt] = []
    private(set) var checkpoints: [MaterialDiagnosticHostingSession.State] = []
    private(set) var events: [String] = []

    func run(_ session: MaterialDiagnosticHostingSession) async {
        await session.run(
            application: { self.application },
            setPolicy: { policy in
                self.policyRequests.append(policy.rawValue)
                self.events.append("policy-\(policy.rawValue)")
                let accessory = policy == .accessory
                self.application = MaterialDiagnosticMetadata.Application(
                    activationPolicy: accessory ? self.accessoryObservedPolicy : self.restorationObservedPolicy,
                    isActive: accessory ? self.accessoryObservedActive : self.restorationObservedActive,
                    isHidden: false, isRunning: false)
                return accessory ? self.accessoryReturnedSuccess : self.restorationReturnedSuccess
            },
            perform: { attempt in
                self.performed.append(attempt)
                self.events.append("capture-\(attempt.ordinal)")
                if self.captureFailureOrdinal == attempt.ordinal {
                    throw MaterialDiagnosticSyntheticHostingFailure.capture(attempt.ordinal)
                }
            },
            checkpoint: {
                let ordinal = self.checkpoints.count + 1
                self.checkpoints.append(session.state)
                self.events.append("checkpoint-\(ordinal)")
                if self.checkpointFailures.contains(ordinal) {
                    throw MaterialDiagnosticSyntheticHostingFailure.checkpoint(ordinal)
                }
            })
    }
}

private enum MaterialDiagnosticSyntheticHostingFailure: Error, CustomStringConvertible {
    case capture(Int)
    case checkpoint(Int)

    var description: String {
        switch self {
        case .capture(let ordinal): return "synthetic-capture-\(ordinal)"
        case .checkpoint(let ordinal): return "synthetic-checkpoint-\(ordinal)"
        }
    }
}
