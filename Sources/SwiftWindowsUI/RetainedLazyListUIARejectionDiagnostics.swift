/// Passive test diagnostics. Entries contain only native scalars and fixed
/// vocabulary; no application object or continuation is retained.
internal struct RetainedLazyListUIARejectionDiagnostics: Equatable {
    enum Site: String {
        case captureEntry, captureTargetIdentity, captureGeometry, captureList, captureLeaves, captureGap
        case captureHintMeasurements, captureMeasurements
        case passEntry, passOwnedScroll, passCounters, passViewport, passGeometry, passLayout, passList, passLeaf
        case queryEntry, queryResult
        case resolveEntry, resolveTarget, resolveScroll, resolveHint, resolveFinal, resolveVisibility
        case settlement
    }

    enum Phase: String {
        case none, prepared, targetQuery, measured, scrolling, finalQuery, resolved, finished
    }

    struct Entry: Equatable {
        let site: Site
        let phase: Phase
        let pass: UInt64
        let sequence: UInt64
        let geometry: UInt64
        let unmutatedGeometry: UInt64?
        let mutation: UInt64
        let rounds: Int
        let remainingRounds: Int
        let remainingElements: Int
        var measurement: RetainedLazyListRuntimeAdapter.MeasurementMatchDiagnostic? = nil

        var line: String {
            "UIA_REJECTION site=\(site.rawValue) phase=\(phase.rawValue) pass=\(pass) sequence=\(sequence)"
                + " geometry=\(geometry) unmutated=\(String(describing: unmutatedGeometry)) mutation=\(mutation)"
                + " rounds=\(rounds) remainingRounds=\(remainingRounds) remainingElements=\(remainingElements)"
                + (measurement.map {
                    " measurementGate=\($0.gate.rawValue) resolutionGate=\($0.resolution?.rawValue ?? "none")"
                        + " resolutionSource=\($0.resolutionSourceIndex.map(String.init) ?? "none")"
                        + " missingRequired=\($0.missingRequiredCount) unmeasuredRecords=\($0.unmeasuredRecordCount)"
                        + " measurementSource=\($0.sourceIndex.map(String.init) ?? "none")"
                } ?? "")
        }
    }

    static let maximumEntries = 64
    var isEnabled = false
    private(set) var entries: [Entry] = []
    private(set) var didDropEntries = false

    mutating func beginOperation() {
        guard isEnabled else { return }
        entries.removeAll(keepingCapacity: true)
        didDropEntries = false
    }

    @discardableResult
    mutating func record(_ entry: Entry) -> Bool {
        guard isEnabled else { return false }
        guard entries.count < Self.maximumEntries else {
            didDropEntries = true
            return false
        }
        entries.append(entry)
        return true
    }
}
