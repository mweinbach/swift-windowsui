import Foundation
import SwiftWindowsGraphics

/// Fixed public diagnostic fixtures, not authorization to observe arbitrary UI text.
public enum NativeBitmapFontFixture: String, Codable, Sendable {
    case symbolPalette = "symbol-palette"
    case stepper
}

enum NativeBitmapFontPurpose: String, Codable, Hashable, Sendable {
    case candidateProbe = "candidate-probe"
    case sentinelProbe = "sentinel-probe"
    case displayBitmap = "display-bitmap"
}

enum NativeBitmapFontRole: String, Codable, Hashable, Sendable {
    case sparkle, bolt, heart, star, folder, chart, globe, checkmark
    case increment, decrement
}

enum NativeBitmapFontBackend: String, Codable, Hashable, Sendable {
    case directWrite = "direct-write"
    case gdi, vector, unknown
    case testingOverride = "testing-override"
}

enum NativeBitmapFontOutcome: String, Codable, Hashable, Sendable {
    case drawProduced = "draw-produced"
    case drawUnavailable = "draw-unavailable"
    case bitmapAccepted = "bitmap-accepted"
    case bitmapRejected = "bitmap-rejected"
    case bitmapCacheHitKnown = "bitmap-cache-hit-known"
    case bitmapCacheHitUnobserved = "bitmap-cache-hit-unobserved"
    case probeCacheHit = "probe-cache-hit"
    case sceneReferenced = "scene-referenced"
    case sceneAssociationUnobserved = "scene-association-unobserved"
    case notReferenced = "not-referenced"
    case vectorSelected = "vector-selected"
    case testingOverride = "testing-override"
}

/// Only bounded values leave the session. No text, glyph identifiers, paths,
/// bitmap tokens, scene coordinates, or event ordering belong in this schema.
public struct NativeBitmapFontAttributionReport: Codable, Sendable {
    public struct Coverage: Codable, Sendable {
        public let bitmapIcons: String
        public let atlasGlyphs: String
        public let textLayouts: String
        public let sceneReferences: String
    }

    public struct Face: Codable, Sendable {
        /// An ID for this metadata record, assigned after sorting metadata.
        /// It is not a COM address, font-face registry ID, or glyph identifier.
        public let id: String
        public let metadata: NativeBitmapFontFaceMetadata
    }

    public struct Observation: Codable, Sendable {
        public let role: String
        public let purpose: String
        public let backend: String
        public let outcome: String
        public let faceIDs: [String]
        public let count: Int
    }

    public struct Limits: Codable, Sendable {
        public let maxFaces: Int
        public let maxReceipts: Int
        public let maxObservations: Int
        public let dropped: Int
    }

    public let schemaVersion: Int
    public let kind: String
    public let scope: String
    public let fixtureID: String
    public let status: String
    public let qualification: String
    public let coverage: Coverage
    public let faces: [Face]
    public let observations: [Observation]
    public let limits: Limits
}

/// The caller owns one session from before component node construction through
/// the selected scene. Environment links and observations hold it weakly.
/// Closing releases every diagnostic COM reference; no process cache is changed.
@MainActor
public final class NativeBitmapFontAttributionSession {
    struct Bounds {
        var faces = 64
        var receipts = 256
        var observations = 256
        var rasterAttempts = 256
        var scenePrimitives = 4096
        var sceneResources = 4096
        var sceneLayers = 1024
        var sceneOperations = 4096
    }

    private struct ObservationKey: Hashable {
        let role: NativeBitmapFontRole
        let purpose: NativeBitmapFontPurpose
        let backend: NativeBitmapFontBackend
        let outcome: NativeBitmapFontOutcome
        let metadataIndices: [Int]
    }

    private struct Receipt {
        let backend: NativeBitmapFontBackend
        let metadataIndices: [Int]
        var acceptedRoles: Set<NativeBitmapFontRole> = []
    }

    public let fixture: NativeBitmapFontFixture
    private let bounds: Bounds
    private let resolveMetadata: @MainActor (NativeFontFaceHandle) -> NativeBitmapFontFaceMetadata
    private var retainedFaces: [UInt: NativeFontFaceHandle] = [:]
    private var faceMetadataIndices: [UInt: Int] = [:]
    private var metadata: [NativeBitmapFontFaceMetadata] = []
    private var receipts: [BitmapContentKey: Receipt] = [:]
    private var observations: [ObservationKey: Int] = [:]
    private var rasterAttempts = 0
    private var dropped = 0
    private var partial = false
    private var scenePartial = false
    private var recording = true
    private var closed = false
    private var finishedReport: NativeBitmapFontAttributionReport?

    public convenience init(fixture: NativeBitmapFontFixture) {
        self.init(fixture: fixture, bounds: Bounds(), resolveMetadata: NativeBitmapFontMetadataResolver.resolve)
    }

    init(
        fixture: NativeBitmapFontFixture,
        bounds: Bounds,
        resolveMetadata: @escaping @MainActor (NativeFontFaceHandle) -> NativeBitmapFontFaceMetadata
    ) {
        self.fixture = fixture
        self.bounds = Bounds(
            faces: min(64, max(0, bounds.faces)),
            receipts: min(256, max(0, bounds.receipts)),
            observations: min(256, max(0, bounds.observations)),
            rasterAttempts: min(256, max(0, bounds.rasterAttempts)),
            scenePrimitives: min(4096, max(0, bounds.scenePrimitives)),
            sceneResources: min(4096, max(0, bounds.sceneResources)),
            sceneLayers: min(1024, max(0, bounds.sceneLayers)),
            sceneOperations: min(4096, max(0, bounds.sceneOperations))
        )
        self.resolveMetadata = resolveMetadata
    }

    /// End construction/selected-scene observation before the snapshotter's
    /// auxiliary frame render. Existing receipts remain available for sealing.
    public func stopRecording() {
        recording = false
    }

    public func close() {
        recording = false
        closed = true
        retainedFaces.removeAll()
        faceMetadataIndices.removeAll()
        receipts.removeAll()
        observations.removeAll()
        metadata.removeAll()
    }

    var retainedFaceCountForTesting: Int { retainedFaces.count }
    var receiptCountForTesting: Int { receipts.count }

    func observation(for symbol: SymbolIcon) -> NativeBitmapFontObservation? {
        guard recording, !closed else { return nil }
        let role: NativeBitmapFontRole
        switch (fixture, symbol) {
        case (.symbolPalette, .sparkle): role = .sparkle
        case (.symbolPalette, .lightning): role = .bolt
        case (.symbolPalette, .heart), (.symbolPalette, .heartFill): role = .heart
        case (.symbolPalette, .star), (.symbolPalette, .starFill): role = .star
        case (.symbolPalette, .folder): role = .folder
        case (.symbolPalette, .activity): role = .chart
        case (.symbolPalette, .globe): role = .globe
        case (.symbolPalette, .checkmark): role = .checkmark
        case (.stepper, .chevronUp): role = .increment
        case (.stepper, .chevronDown): role = .decrement
        default: return nil
        }
        return NativeBitmapFontObservation(owner: self, role: role, purpose: .displayBitmap)
    }

    fileprivate func beginDirectWriteCapture() -> NativeBitmapFontDrawCapture? {
        guard recording, !closed else { return nil }
        guard rasterAttempts < bounds.rasterAttempts else {
            noteDropped()
            return nil
        }
        rasterAttempts += 1
        return NativeBitmapFontDrawCapture(maxFaces: min(8, bounds.faces))
    }

    fileprivate func completeDirectWriteCapture(
        _ capture: NativeBitmapFontDrawCapture?, bitmap: BitmapSurface?, observation: NativeBitmapFontObservation
    ) {
        guard recording, !closed else { return }
        var indices: Set<Int> = []
        if let capture {
            if capture.truncated { noteDropped() }
            for face in capture.faces {
                let address = face.faceAddress
                if let index = faceMetadataIndices[address] {
                    indices.insert(index)
                    continue
                }
                guard retainedFaces.count < bounds.faces else {
                    noteDropped()
                    continue
                }
                let value = resolveMetadata(face)
                guard recording, !closed else { return }
                let index: Int
                if let existing = metadata.firstIndex(of: value) {
                    index = existing
                } else {
                    index = metadata.count
                    metadata.append(value)
                }
                retainedFaces[address] = face
                faceMetadataIndices[address] = index
                indices.insert(index)
            }
            if capture.drawFailures > 0 || capture.drawCount == 0 { partial = true }
        } else {
            partial = true
        }
        let sortedIndices = indices.sorted()
        if sortedIndices.isEmpty { partial = true }
        record(
            observation, backend: .directWrite, outcome: bitmap == nil ? .drawUnavailable : .drawProduced,
            metadataIndices: sortedIndices
        )
        if observation.purpose == .displayBitmap, let bitmap {
            storeReceipt(bitmap, backend: .directWrite, metadataIndices: sortedIndices)
        }
    }

    fileprivate func recordUnknownRaster(
        _ bitmap: BitmapSurface?, backend: NativeBitmapFontBackend, observation: NativeBitmapFontObservation
    ) {
        guard recording, !closed else { return }
        partial = true
        record(
            observation, backend: backend,
            outcome: backend == .testingOverride ? .testingOverride : (bitmap == nil ? .drawUnavailable : .drawProduced)
        )
        if observation.purpose == .displayBitmap, let bitmap {
            storeReceipt(bitmap, backend: backend, metadataIndices: [])
        }
    }

    fileprivate func noteProbeCacheHit(_ observation: NativeBitmapFontObservation) {
        guard recording, !closed else { return }
        record(observation, backend: .unknown, outcome: .probeCacheHit)
    }

    fileprivate func accept(_ bitmap: BitmapSurface, cacheHit: Bool, observation: NativeBitmapFontObservation) {
        guard recording, !closed else { return }
        if var receipt = receipts[bitmap.contentKey] {
            receipt.acceptedRoles.insert(observation.role)
            receipts[bitmap.contentKey] = receipt
            record(
                observation, backend: receipt.backend,
                outcome: cacheHit ? .bitmapCacheHitKnown : .bitmapAccepted,
                metadataIndices: receipt.metadataIndices
            )
        } else {
            partial = true
            record(
                observation, backend: .unknown,
                outcome: cacheHit ? .bitmapCacheHitUnobserved : .bitmapAccepted
            )
            storeReceipt(bitmap, backend: .unknown, metadataIndices: [])
            if var receipt = receipts[bitmap.contentKey] {
                receipt.acceptedRoles.insert(observation.role)
                receipts[bitmap.contentKey] = receipt
            }
        }
    }

    fileprivate func reject(_ bitmap: BitmapSurface?, observation: NativeBitmapFontObservation) {
        guard recording, !closed else { return }
        let receipt = bitmap.flatMap { receipts[$0.contentKey] }
        record(
            observation, backend: receipt?.backend ?? .unknown, outcome: .bitmapRejected,
            metadataIndices: receipt?.metadataIndices ?? []
        )
    }

    fileprivate func selectVector(_ observation: NativeBitmapFontObservation) {
        guard recording, !closed else { return }
        // The chosen node route is known; vector contribution to final pixels
        // is outside the bitmap-resource association implemented in this mode.
        partial = true
        scenePartial = true
        record(observation, backend: .vector, outcome: .vectorSelected)
    }

    private func storeReceipt(_ bitmap: BitmapSurface, backend: NativeBitmapFontBackend, metadataIndices: [Int]) {
        if let existing = receipts[bitmap.contentKey] {
            // A copy reuses its receipt. Conflicting production claims for
            // one immutable content token cannot strengthen its ownership.
            if existing.backend != backend || existing.metadataIndices != metadataIndices {
                partial = true
                receipts[bitmap.contentKey] = Receipt(
                    backend: .unknown, metadataIndices: [], acceptedRoles: existing.acceptedRoles)
            }
            return
        }
        guard receipts.count < bounds.receipts else {
            noteDropped()
            return
        }
        receipts[bitmap.contentKey] = Receipt(backend: backend, metadataIndices: metadataIndices)
    }

    private func noteDropped() {
        partial = true
        if dropped < Int.max { dropped += 1 }
    }

    private func record(
        _ observation: NativeBitmapFontObservation,
        backend: NativeBitmapFontBackend,
        outcome: NativeBitmapFontOutcome,
        metadataIndices: [Int] = []
    ) {
        let key = ObservationKey(
            role: observation.role, purpose: observation.purpose, backend: backend,
            outcome: outcome, metadataIndices: metadataIndices
        )
        if let count = observations[key] {
            observations[key] = count < Int.max ? count + 1 : count
        } else if observations.count < bounds.observations {
            observations[key] = 1
        } else {
            noteDropped()
        }
    }

    /// Stage 1 associates top-level bitmap resources only. Atlas glyphs,
    /// nested render-pass sources, and visible-pixel ownership stay explicit
    /// gaps; no scene or renderer contract is changed to improve attribution.
    public func finish(scene: GPUIScene) -> NativeBitmapFontAttributionReport {
        if let finishedReport { return finishedReport }
        recording = false
        if closed {
            partial = true
            scenePartial = true
        }
        var referenced: Set<BitmapContentKey> = []
        var structureBounded = scene.layers.count <= bounds.sceneLayers
        if structureBounded {
            var operations = 0
            for layer in scene.layers {
                guard layer.paintOperationCount <= bounds.sceneOperations - operations else {
                    structureBounded = false
                    break
                }
                operations += layer.paintOperationCount
            }
        }
        // The iterator can skip empty layers/invalid operations without
        // yielding a primitive. Bound those inputs before starting it.
        if !structureBounded || scene.imageResources.count > bounds.sceneResources
            || scene.imageRenderPasses.count > bounds.sceneResources
        {
            noteDropped()
            scenePartial = true
        } else {
            var visited = 0
            sceneLoop: for run in scene.presentationOrder() {
                for index in run.range {
                    guard visited < bounds.scenePrimitives else {
                        noteDropped()
                        scenePartial = true
                        break sceneLoop
                    }
                    visited += 1
                    guard let primitive = scene.primitive(kind: run.kind, inLayer: run.layerIndex, at: index) else {
                        scenePartial = true
                        continue
                    }
                    guard case .image(let image) = primitive else { continue }
                    if scene.imageRenderPasses.contains(where: { $0.textureID == image.textureID }) {
                        scenePartial = true
                    } else if let resource = scene.imageResources.last(where: { $0.textureID == image.textureID }) {
                        referenced.insert(resource.bitmap.contentKey)
                    } else {
                        // A pass source is not a static image. Do not borrow a
                        // same-numbered texture from a different namespace.
                        scenePartial = true
                    }
                }
            }
        }
        for (key, receipt) in receipts {
            for role in receipt.acceptedRoles {
                record(
                    NativeBitmapFontObservation(owner: self, role: role, purpose: .displayBitmap),
                    backend: receipt.backend,
                    outcome: referenced.contains(key)
                        ? .sceneReferenced : (scenePartial ? .sceneAssociationUnobserved : .notReferenced),
                    metadataIndices: receipt.metadataIndices
                )
            }
        }
        if observations.isEmpty { partial = true }
        let expectedRoles: Set<NativeBitmapFontRole> =
            fixture == .symbolPalette
            ? [.sparkle, .bolt, .heart, .star, .folder, .chart, .globe, .checkmark] : [.increment, .decrement]
        let representedRoles = Set(
            observations.keys.filter {
                $0.purpose == .displayBitmap
                    && [.bitmapAccepted, .bitmapCacheHitKnown, .bitmapCacheHitUnobserved, .vectorSelected].contains(
                        $0.outcome)
            }.map(\.role))
        if !expectedRoles.isSubset(of: representedRoles) { partial = true }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sortedMetadata = metadata.enumerated().sorted { left, right in
            let leftKey = (try? encoder.encode(left.element)) ?? Data()
            let rightKey = (try? encoder.encode(right.element)) ?? Data()
            return leftKey.lexicographicallyPrecedes(rightKey)
        }
        var identifiers: [Int: String] = [:]
        let faces = sortedMetadata.enumerated().map { ordinal, entry in
            let identifier = "face-\(ordinal + 1)"
            identifiers[entry.offset] = identifier
            return NativeBitmapFontAttributionReport.Face(id: identifier, metadata: entry.element)
        }
        let outputObservations = observations.map { key, count in
            NativeBitmapFontAttributionReport.Observation(
                role: key.role.rawValue, purpose: key.purpose.rawValue, backend: key.backend.rawValue,
                outcome: key.outcome.rawValue,
                faceIDs: key.metadataIndices.compactMap { identifiers[$0] }.sorted(), count: count
            )
        }.sorted { left, right in
            [left.role, left.purpose, left.backend, left.outcome, left.faceIDs.joined(separator: ",")]
                .lexicographicallyPrecedes(
                    [right.role, right.purpose, right.backend, right.outcome, right.faceIDs.joined(separator: ",")])
        }
        let report = NativeBitmapFontAttributionReport(
            schemaVersion: 1, kind: "native-bitmap-font-attribution", scope: "bitmap-icons",
            fixtureID: fixture.rawValue, status: partial || scenePartial ? "partial" : "observed",
            qualification: "unqualified",
            coverage: .init(
                bitmapIcons: partial ? "partial" : "observed", atlasGlyphs: "not-instrumented",
                textLayouts: "not-instrumented", sceneReferences: scenePartial ? "partial" : "observed"
            ),
            faces: faces, observations: outputObservations,
            limits: .init(
                maxFaces: bounds.faces, maxReceipts: bounds.receipts,
                maxObservations: bounds.observations, dropped: dropped
            )
        )
        close()
        finishedReport = report
        return report
    }
}

/// Values in this context come only from the fixed fixture/symbol allowlist.
/// It never contains source text or retains its session owner.
@MainActor
struct NativeBitmapFontObservation {
    weak var owner: NativeBitmapFontAttributionSession?
    let role: NativeBitmapFontRole
    let purpose: NativeBitmapFontPurpose

    func withPurpose(_ purpose: NativeBitmapFontPurpose) -> Self {
        Self(owner: owner, role: role, purpose: purpose)
    }

    func beginDirectWriteCapture() -> NativeBitmapFontDrawCapture? { owner?.beginDirectWriteCapture() }

    func completeDirectWriteCapture(_ capture: NativeBitmapFontDrawCapture?, bitmap: BitmapSurface?) {
        owner?.completeDirectWriteCapture(capture, bitmap: bitmap, observation: self)
    }

    func recordGDIResult(bitmap: BitmapSurface?) {
        owner?.recordUnknownRaster(bitmap, backend: .gdi, observation: self)
    }

    func recordTestingOverrideResult(bitmap: BitmapSurface?) {
        owner?.recordUnknownRaster(bitmap, backend: .testingOverride, observation: self)
    }

    func noteProbeCacheHit() { owner?.noteProbeCacheHit(self) }
    func accept(_ bitmap: BitmapSurface, cacheHit: Bool) {
        owner?.accept(bitmap, cacheHit: cacheHit, observation: self)
    }
    func reject(_ bitmap: BitmapSurface?) { owner?.reject(bitmap, observation: self) }
    func selectVector() { owner?.selectVector(self) }
}
