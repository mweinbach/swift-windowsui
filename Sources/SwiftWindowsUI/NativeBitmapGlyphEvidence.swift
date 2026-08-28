import Foundation
import SwiftWindowsGraphics

/// V2 is an explicit diagnostic opt-in. It does not change the default V1
/// schema, and neither version qualifies a font profile or pixel baseline.
public enum NativeBitmapFontAttributionVersion: Int, Sendable {
    case v1 = 1
    case v2 = 2
}

/// Actual display-bitmap glyph runs, kept separate from the V1 metadata report.
/// IDs are local to this report and are assigned after content sorting. They
/// are not addresses, persistent font identities, cache keys, or event order.
public struct NativeBitmapFontAttributionReportV2: Encodable, Sendable {
    public struct Coverage: Encodable, Sendable {
        public let bitmapDrawGlyphRuns: String
        public let faceFileStreams: String
        public let sceneReferences: String
        public let atlasGlyphs: String
        public let textLayouts: String
        public let visiblePixels: String
        public let loadedBytesDigest: String
    }

    public struct Face: Encodable, Sendable {
        public let id: String
        public let metadata: NativeBitmapFontFaceMetadata
        public let evidence: NativeBitmapFontFaceEvidenceV2
    }

    public struct GlyphRun: Encodable, Sendable {
        public let id: String
        public let faceID: String
        public let glyphCount: Int
        public let glyphIndices: [UInt16]
        public let drawResult: Int32
        public let drawStatus: String
        /// Number of copied callbacks with this same face, array, and result.
        public let count: Int
    }

    public struct Observation: Encodable, Sendable {
        public let role: String
        public let purpose: String
        public let backend: String
        public let outcome: String
        public let status: String
        public let runIDs: [String]
        /// Per-attempt multiplicity, parallel to runIDs. Association counts do
        /// not imply new draws: a known cache receipt can be referenced again.
        public let runCounts: [Int]
        public let count: Int
    }

    public struct Limits: Encodable, Sendable {
        public let maxFaces: Int
        public let maxReceipts: Int
        public let maxObservations: Int
        public let maxGlyphsPerRun: Int
        public let maxRunsPerRaster: Int
        public let maxRuns: Int
        public let maxGlyphs: Int
        public let maxFilesPerFace: Int
        public let maxAxesPerFace: Int
        public let maxStreamBytesPerFile: UInt64
        public let maxStreamBytesSession: UInt64
        public let streamFragmentBytes: UInt64
        public let copiedRuns: Int
        public let copiedGlyphs: Int
        public let requestedStreamBytes: UInt64
        public let readStreamBytes: UInt64
        public let dropped: Int
    }

    public let schemaVersion: Int
    public let kind: String
    public let scope: String
    public let fixtureID: String
    public let status: String
    public let qualification: String
    /// The original report retains its exact V1 schema and privacy boundary.
    public let attributionV1: NativeBitmapFontAttributionReport
    public let coverage: Coverage
    public let faces: [Face]
    public let glyphRuns: [GlyphRun]
    public let observations: [Observation]
    public let limits: Limits
}

/// One session owns every retained face and private bitmap receipt. Only
/// display-bitmap callbacks enter this state; probes cannot supply glyph IDs
/// or ownership for accepted bitmaps, even when their metadata happens to match.
@MainActor
final class NativeBitmapGlyphEvidenceSession {
    typealias EvidenceResolver =
        @MainActor (
            NativeFontFaceHandle, inout NativeBitmapFontStreamBudget
        ) -> NativeBitmapFontFaceEvidenceV2

    private struct FaceRecord {
        let handle: NativeFontFaceHandle
        let metadata: NativeBitmapFontFaceMetadata
        let evidence: NativeBitmapFontFaceEvidenceV2
        let tieBreak: Int
    }

    private struct RunKey: Hashable {
        let faceIndex: Int
        let glyphIndices: [UInt16]
        let drawResult: Int32

        var valueKey: String {
            "\(drawResult):" + glyphIndices.map(String.init).joined(separator: ",")
        }
    }

    private struct RunUse: Hashable {
        let run: RunKey
        let count: Int
    }

    private struct Receipt {
        let backend: NativeBitmapFontBackend
        let runs: [RunUse]
        let status: String
        var acceptedRoles: Set<NativeBitmapFontRole> = []
    }

    private struct ObservationKey: Hashable {
        let role: NativeBitmapFontRole
        let backend: NativeBitmapFontBackend
        let outcome: NativeBitmapFontOutcome
        let status: String
        let runs: [RunUse]
    }

    private struct FaceSortValue: Encodable {
        let metadata: NativeBitmapFontFaceMetadata
        let evidence: NativeBitmapFontFaceEvidenceV2
        let runUses: [String]
        let associations: [String]
        let refinementClass: Int
    }

    let captureBudget = NativeBitmapGlyphCaptureBudget()
    // Unique private ranks sampled with the standard system random generator.
    // A fixed-size permutation avoids collision retries. It is created only
    // for V2 and is never encoded or used as a time/address fallback.
    private let faceTieBreaks = Array(0..<64).shuffled()
    private let resolveEvidence: EvidenceResolver
    private var streamBudget = NativeBitmapFontStreamBudget()
    private var faces: [FaceRecord] = []
    private var faceIndices: [UInt: Int] = [:]
    private var runs: [RunKey: Int] = [:]
    private var receipts: [BitmapContentKey: Receipt] = [:]
    private var observations: [ObservationKey: Int] = [:]
    private var partial = false
    private var dropped = 0
    private var closed = false

    init(resolveEvidence: @escaping EvidenceResolver = NativeBitmapFontMetadataResolver.resolveV2) {
        self.resolveEvidence = resolveEvidence
    }

    func close() {
        closed = true
        captureBudget.close()
        faces.removeAll()
        faceIndices.removeAll()
        runs.removeAll()
        receipts.removeAll()
        observations.removeAll()
    }

    func complete(
        _ capture: NativeBitmapFontDrawCapture?, bitmap: BitmapSurface?, observation: NativeBitmapFontObservation,
        metadata: (NativeFontFaceHandle) -> NativeBitmapFontFaceMetadata?
    ) {
        guard !closed, observation.purpose == .displayBitmap else { return }
        var membership: [RunKey: Int] = [:]
        var incomplete = true
        if let capture, capture.consumeGlyphRuns(for: captureBudget, role: observation.role) {
            incomplete = false
            incomplete = incomplete || capture.glyphsIncomplete || capture.truncated || capture.drawCount == 0
            for captured in capture.glyphRuns {
                let address = captured.face.faceAddress
                let index: Int
                if let existing = faceIndices[address] {
                    index = existing
                } else {
                    guard faces.count < 64 else {
                        noteDropped()
                        incomplete = true
                        continue
                    }
                    guard let value = metadata(captured.face) else {
                        // Share the original session's 64-face retention bound,
                        // including probe faces. V2 does not add a second quota.
                        noteDropped()
                        incomplete = true
                        continue
                    }
                    let evidence = resolveEvidence(captured.face, &streamBudget)
                    guard !closed else { return }
                    index = faces.count
                    // Do not merge different retained pointers on equal names,
                    // file references, or unknown metadata. The handle prevents
                    // pointer reuse during this observation session.
                    faces.append(
                        FaceRecord(
                            handle: captured.face, metadata: value, evidence: evidence, tieBreak: faceTieBreaks[index]))
                    faceIndices[address] = index
                }
                let key = RunKey(
                    faceIndex: index, glyphIndices: captured.glyphIndices, drawResult: captured.drawResult)
                runs[key, default: 0] += 1
                membership[key, default: 0] += 1
            }
        } else if capture != nil {
            noteDropped()
        }
        let uses = sortedUses(membership)
        let status = uses.isEmpty ? "not-observed" : (incomplete ? "partial" : "observed")
        if status != "observed" { partial = true }
        record(
            role: observation.role, backend: .directWrite,
            outcome: bitmap == nil ? .drawUnavailable : .drawProduced, status: status, runs: uses)
        if let bitmap {
            storeReceipt(bitmap, backend: .directWrite, runs: uses, status: status)
        }
    }

    func unknownRaster(
        _ bitmap: BitmapSurface?, backend: NativeBitmapFontBackend, observation: NativeBitmapFontObservation
    ) {
        guard !closed, observation.purpose == .displayBitmap else { return }
        partial = true
        record(
            role: observation.role, backend: backend,
            outcome: backend == .testingOverride
                ? .testingOverride : (bitmap == nil ? .drawUnavailable : .drawProduced),
            status: "not-observed")
        if let bitmap { storeReceipt(bitmap, backend: backend, runs: [], status: "not-observed") }
    }

    func accept(_ bitmap: BitmapSurface, cacheHit: Bool, observation: NativeBitmapFontObservation) {
        guard !closed, observation.purpose == .displayBitmap else { return }
        if var receipt = receipts[bitmap.contentKey] {
            receipt.acceptedRoles.insert(observation.role)
            receipts[bitmap.contentKey] = receipt
            record(
                role: observation.role, backend: receipt.backend,
                outcome: cacheHit ? .bitmapCacheHitKnown : .bitmapAccepted,
                status: receipt.status, runs: receipt.runs)
        } else {
            partial = true
            record(
                role: observation.role, backend: .unknown,
                outcome: cacheHit ? .bitmapCacheHitUnobserved : .bitmapAccepted, status: "not-observed")
            storeReceipt(bitmap, backend: .unknown, runs: [], status: "not-observed")
            if var receipt = receipts[bitmap.contentKey] {
                receipt.acceptedRoles.insert(observation.role)
                receipts[bitmap.contentKey] = receipt
            }
        }
    }

    func reject(_ bitmap: BitmapSurface?, observation: NativeBitmapFontObservation) {
        guard !closed, observation.purpose == .displayBitmap else { return }
        let receipt = bitmap.flatMap { receipts[$0.contentKey] }
        record(
            role: observation.role, backend: receipt?.backend ?? .unknown, outcome: .bitmapRejected,
            status: receipt?.status ?? "not-observed", runs: receipt?.runs ?? [])
    }

    func selectVector(_ observation: NativeBitmapFontObservation) {
        guard !closed, observation.purpose == .displayBitmap else { return }
        partial = true
        record(role: observation.role, backend: .vector, outcome: .vectorSelected, status: "not-observed")
    }

    private func storeReceipt(
        _ bitmap: BitmapSurface, backend: NativeBitmapFontBackend, runs: [RunUse], status: String
    ) {
        if let existing = receipts[bitmap.contentKey] {
            if existing.backend != backend || existing.runs != runs || existing.status != status {
                partial = true
                receipts[bitmap.contentKey] = Receipt(
                    backend: .unknown, runs: [], status: "not-observed", acceptedRoles: existing.acceptedRoles)
            }
            return
        }
        guard receipts.count < 256 else {
            noteDropped()
            return
        }
        receipts[bitmap.contentKey] = Receipt(backend: backend, runs: runs, status: status)
    }

    private func record(
        role: NativeBitmapFontRole, backend: NativeBitmapFontBackend, outcome: NativeBitmapFontOutcome,
        status: String, runs: [RunUse] = []
    ) {
        let key = ObservationKey(role: role, backend: backend, outcome: outcome, status: status, runs: runs)
        if let count = observations[key] {
            observations[key] = count < Int.max ? count + 1 : count
        } else if observations.count < 256 {
            observations[key] = 1
        } else {
            noteDropped()
        }
    }

    private func noteDropped() {
        partial = true
        if dropped < Int.max { dropped += 1 }
    }

    private func sortedUses(_ bag: [RunKey: Int]) -> [RunUse] {
        bag.map { RunUse(run: $0.key, count: $0.value) }.sorted {
            if $0.run.faceIndex != $1.run.faceIndex { return $0.run.faceIndex < $1.run.faceIndex }
            return $0.run.valueKey < $1.run.valueKey
        }
    }

    func finish(
        attributionV1: NativeBitmapFontAttributionReport,
        referenced: Set<BitmapContentKey>, scenePartial: Bool
    ) -> NativeBitmapFontAttributionReportV2 {
        if closed { partial = true }
        for (key, receipt) in receipts {
            for role in receipt.acceptedRoles {
                let outcome: NativeBitmapFontOutcome =
                    referenced.contains(key)
                    ? .sceneReferenced : (scenePartial ? .sceneAssociationUnobserved : .notReferenced)
                record(
                    role: role, backend: receipt.backend,
                    outcome: outcome,
                    status: outcome == .sceneAssociationUnobserved ? "not-observed" : receipt.status,
                    runs: outcome == .sceneAssociationUnobserved ? [] : receipt.runs)
            }
        }
        if observations.isEmpty || attributionV1.coverage.bitmapIcons != "observed"
            || observations.keys.contains(where: { $0.status != "observed" })
        {
            partial = true
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let faceKeys = refinedFaceSortKeys(encoder: encoder)
        let sortedFaces = faces.enumerated().sorted { left, right in
            if faceKeys[left.offset] != faceKeys[right.offset] {
                return faceKeys[left.offset].lexicographicallyPrecedes(faceKeys[right.offset])
            }
            // Residual graph symmetries are not a claim of identical physical
            // faces. Keep both records without publishing their encounter order.
            return left.element.tieBreak < right.element.tieBreak
        }
        var faceIDs: [Int: String] = [:]
        let outputFaces = sortedFaces.enumerated().map { ordinal, entry in
            let identifier = "draw-face-\(ordinal + 1)"
            faceIDs[entry.offset] = identifier
            return NativeBitmapFontAttributionReportV2.Face(
                id: identifier, metadata: entry.element.metadata, evidence: entry.element.evidence)
        }
        let sortedRuns = runs.sorted { left, right in
            [faceIDs[left.key.faceIndex] ?? "", left.key.valueKey]
                .lexicographicallyPrecedes([faceIDs[right.key.faceIndex] ?? "", right.key.valueKey])
        }
        var runIDs: [RunKey: String] = [:]
        let outputRuns = sortedRuns.enumerated().map { ordinal, entry in
            let identifier = "glyph-run-\(ordinal + 1)"
            runIDs[entry.key] = identifier
            return NativeBitmapFontAttributionReportV2.GlyphRun(
                id: identifier, faceID: faceIDs[entry.key.faceIndex] ?? "",
                glyphCount: entry.key.glyphIndices.count, glyphIndices: entry.key.glyphIndices,
                drawResult: entry.key.drawResult, drawStatus: entry.key.drawResult >= 0 ? "succeeded" : "failed",
                count: entry.value)
        }
        let outputObservations = observations.map { key, count in
            let uses = key.runs.map { (id: runIDs[$0.run] ?? "", count: $0.count) }.sorted { $0.id < $1.id }
            return NativeBitmapFontAttributionReportV2.Observation(
                role: key.role.rawValue, purpose: NativeBitmapFontPurpose.displayBitmap.rawValue,
                backend: key.backend.rawValue, outcome: key.outcome.rawValue, status: key.status,
                runIDs: uses.map(\.id), runCounts: uses.map(\.count), count: count)
        }.sorted { left, right in
            let leftData = (try? encoder.encode(left)) ?? Data()
            let rightData = (try? encoder.encode(right)) ?? Data()
            return leftData.lexicographicallyPrecedes(rightData)
        }
        let streamsObserved =
            !faces.isEmpty
            && faces.allSatisfy {
                $0.evidence.filesStatus == .observed && !$0.evidence.files.isEmpty
                    && $0.evidence.files.allSatisfy { $0.status == .observed }
            }
        let axesObserved = faces.allSatisfy { $0.evidence.axesStatus == .observed }
        let metadataObserved = faces.allSatisfy {
            $0.metadata.namesStatus == .observed && $0.metadata.faceIndex != nil
                && $0.metadata.simulations != nil && $0.evidence.faceType != nil
        }
        let reportedRuns = runs.values.reduce(0, +)
        let reportedGlyphs = runs.reduce(0) { $0 + $1.key.glyphIndices.count * $1.value }
        if reportedRuns != captureBudget.copiedRuns || reportedGlyphs != captureBudget.copiedGlyphs {
            // A copied capture may have been abandoned or rejected before it
            // supplied a receipt. Keep the charged budget, report the omission,
            // and never invent a completed draw to balance these counters.
            noteDropped()
        }
        let allDropped = dropped > Int.max - captureBudget.dropped ? Int.max : dropped + captureBudget.dropped
        let glyphsPartial = partial || allDropped > 0
        return NativeBitmapFontAttributionReportV2(
            schemaVersion: 2, kind: "native-bitmap-font-attribution-v2", scope: "bitmap-icons",
            fixtureID: attributionV1.fixtureID,
            status: glyphsPartial || !streamsObserved || !axesObserved || !metadataObserved || scenePartial
                ? "partial" : "observed",
            qualification: "unqualified", attributionV1: attributionV1,
            coverage: .init(
                bitmapDrawGlyphRuns: glyphsPartial ? "partial" : "observed",
                faceFileStreams: streamsObserved ? "observed" : "partial",
                sceneReferences: scenePartial ? "partial" : "observed", atlasGlyphs: "not-instrumented",
                textLayouts: "not-instrumented", visiblePixels: "not-observed", loadedBytesDigest: "not-observed"),
            faces: outputFaces, glyphRuns: outputRuns, observations: outputObservations,
            limits: .init(
                maxFaces: 64, maxReceipts: 256, maxObservations: 256,
                maxGlyphsPerRun: NativeBitmapGlyphCaptureBudget.maximumGlyphsPerRun,
                maxRunsPerRaster: NativeBitmapGlyphCaptureBudget.maximumRunsPerRaster,
                maxRuns: NativeBitmapGlyphCaptureBudget.maximumRuns,
                maxGlyphs: NativeBitmapGlyphCaptureBudget.maximumGlyphs,
                maxFilesPerFace: 8, maxAxesPerFace: 32,
                maxStreamBytesPerFile: 16_777_216, maxStreamBytesSession: 67_108_864, streamFragmentBytes: 65_536,
                copiedRuns: captureBudget.copiedRuns, copiedGlyphs: captureBudget.copiedGlyphs,
                requestedStreamBytes: streamBudget.requestedBytes, readStreamBytes: streamBudget.readBytes,
                dropped: allDropped)
        )
    }

    private func refinedFaceSortKeys(encoder: JSONEncoder) -> [Data] {
        var classes = Array(repeating: 0, count: faces.count)
        var keys: [Data] = []
        // Refinement propagates distinguishing co-run context across the
        // bounded graph. It is not an unbounded graph-isomorphism search.
        for _ in 0..<max(1, faces.count) {
            keys = faces.enumerated().map {
                faceSortKey($0.offset, record: $0.element, classes: classes, encoder: encoder)
            }
            let distinct = Set(keys).sorted { $0.lexicographicallyPrecedes($1) }
            let ranks = Dictionary(uniqueKeysWithValues: distinct.enumerated().map { ($0.element, $0.offset) })
            let next = keys.map { ranks[$0] ?? 0 }
            if next == classes { break }
            classes = next
        }
        return keys
    }

    private func faceSortKey(_ index: Int, record: FaceRecord, classes: [Int], encoder: JSONEncoder) -> Data {
        let runUses = runs.filter { $0.key.faceIndex == index }.map {
            "\($0.key.valueKey):\($0.value)"
        }.sorted()
        let associations = observations.compactMap { key, count -> String? in
            let uses = key.runs.filter { $0.run.faceIndex == index }.map {
                "\($0.run.valueKey):\($0.count)"
            }.sorted()
            guard !uses.isEmpty else { return nil }
            // Include the complete co-run context, not only this face's slice.
            // Equal metadata faces used alongside different actual faces must
            // not acquire IDs according to which raster attempt happened first.
            let context = key.runs.map { use in
                [
                    use.run.faceIndex == index ? "self" : "peer", String(classes[use.run.faceIndex]),
                    use.run.valueKey, String(use.count),
                ].joined(separator: "|")
            }.sorted().joined(separator: "\n")
            return [
                key.role.rawValue, key.backend.rawValue, key.outcome.rawValue, key.status,
                uses.joined(separator: ";"), context, String(count),
            ].joined(separator: "|")
        }.sorted()
        return
            (try? encoder.encode(
                FaceSortValue(
                    metadata: record.metadata, evidence: record.evidence, runUses: runUses, associations: associations,
                    refinementClass: classes[index])))
            ?? Data()
    }
}
