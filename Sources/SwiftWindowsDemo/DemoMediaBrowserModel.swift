import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

public struct DemoMediaBrowserRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let source: DemoMediaImageSource
    fileprivate var revision: UInt64

    public var sourceDescription: String {
        if case .data = source { return "Built-in sample" }
        return "Local file"
    }

    /// The two PNGs are the existing demo's owned caps/tile resources, embedded
    /// as encoded source bytes. No bundle read, decode, or task occurs here.
    public static var samples: [Self] {
        [
            Self(
                id: "sample:corners", name: "Corner study.png",
                source: .data(
                    Data(
                        base64Encoded:
                            "iVBORw0KGgoAAAANSUhEUgAAABgAAAAQCAYAAAAMJL+VAAAAf0lEQVR42mN4EBv+Hxl3LnsIxmevvQdjUvlftwahYIZRCwhacChv7n9kLK/vhILto0pRMCH51RPCUTDtLXh7/sF/ZEypBc9ubETBtLcAPYhINRBdnmAcUN0C9CCi1AKCcUB1C9zXLfqPjKN7i8B4160jYEwqP6X3NgoetYCgBQDs+OZ+0sF9yQAAAABJRU5ErkJggg=="
                    )!), revision: 0),
            Self(
                id: "sample:tiles", name: "Tile study.png",
                source: .data(
                    Data(
                        base64Encoded:
                            "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAFCAYAAACJmvbYAAAALElEQVR42mNwX7foPwjL6zv9T+m9jUIzwCTRJUA0AzYdcJ24JPDq/Lo16D8AEDFOmrESu5IAAAAASUVORK5CYII="
                    )!), revision: 0),
            Self(id: "sample:broken", name: "Truncated image.png", source: .data(Data([137, 80, 78])), revision: 0),
            Self(
                id: "sample:unsupported", name: "Unsupported format.gif",
                source: .data(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==")!),
                revision: 0),
        ]
    }
}

public enum DemoMediaBrowserLayout: String, CaseIterable, Equatable, Sendable { case grid, list }
public enum DemoMediaBrowserLoadPhase: Equatable, Sendable { case idle, loading, ready, failed, cancelled }

public enum DemoMediaBrowserLoadState: Sendable {
    case idle
    case loading
    case ready(DemoMediaImage)
    case failed(String)
    case cancelled

    public var phase: DemoMediaBrowserLoadPhase {
        switch self {
        case .idle: return .idle
        case .loading: return .loading
        case .ready: return .ready
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }
}

public struct DemoMediaBrowserSnapshot: Sendable {
    public fileprivate(set) var records: [DemoMediaBrowserRecord]
    public fileprivate(set) var selectedID: String?
    public fileprivate(set) var pageIndex: Int
    public fileprivate(set) var pageScope: UUID
    public fileprivate(set) var layout: DemoMediaBrowserLayout
    public fileprivate(set) var thumbnails: [String: DemoMediaBrowserLoadState]
    public fileprivate(set) var preview: DemoMediaBrowserLoadState
    public fileprivate(set) var notice: String?
}

/// A window owns this model and its service. Explicit four-record pages and
/// geometry visibility bound demand; one preview and one thumbnail lane retain
/// their occupied slots until the awaited service calls actually return.
@MainActor
public final class DemoMediaBrowserModel: ObservableObject {
    public static let maximumRecordCount = 64
    public static let pageSize = 4
    public static let thumbnailPixelDimension = 256
    public static let previewPixelDimension = 1024

    @Published private var changeSignal: UInt = 0
    private var current: DemoMediaBrowserSnapshot
    private let service: DemoMediaImageService
    private var currentMountID: UUID?
    private var lifetime: DemoMediaBrowserLifetime?
    private var previewJob: DemoMediaBrowserJob?
    private var thumbnailJob: DemoMediaBrowserJob?
    private var desiredPreview: DemoMediaBrowserRequest?
    private var desiredThumbnails: [String: DemoMediaBrowserRequest] = [:]
    private var visibleThumbnailIDs: Set<String> = []
    private var browserVisible = false
    private var previewVisible = false
    private var nextRevision: UInt64? = 1
    private var shutdownTask: Task<Void, Never>?
    public private(set) var isClosed = false

    public init(service: DemoMediaImageService = DemoMediaImageService(), includesSamples: Bool = true) {
        self.service = service
        let records = includesSamples ? DemoMediaBrowserRecord.samples : []
        current = DemoMediaBrowserSnapshot(
            records: records, selectedID: records.first?.id, pageIndex: 0, pageScope: UUID(), layout: .grid,
            thumbnails: Dictionary(uniqueKeysWithValues: records.prefix(Self.pageSize).map { ($0.id, .idle) }),
            preview: .idle, notice: nil)
    }

    isolated deinit {
        lifetime?.cancel()
        previewJob?.task.cancel()
        thumbnailJob?.task.cancel()
        shutdownTask?.cancel()
    }

    public var snapshot: DemoMediaBrowserSnapshot { current }
    public var records: [DemoMediaBrowserRecord] { current.records }
    public var selectedID: String? { current.selectedID }
    public var selectedRecord: DemoMediaBrowserRecord? { current.records.first { $0.id == current.selectedID } }
    public var pageIndex: Int { current.pageIndex }
    public var pageScope: UUID { current.pageScope }
    public var pageCount: Int { max(1, (current.records.count + Self.pageSize - 1) / Self.pageSize) }
    public var layout: DemoMediaBrowserLayout { current.layout }
    public var preview: DemoMediaBrowserLoadState { current.preview }
    public var notice: String? { current.notice }
    public var isActive: Bool { !isClosed && currentMountID != nil && lifetime?.isFinished == false && browserVisible }
    public var isReading: Bool { previewJob != nil || thumbnailJob != nil }
    public var isPreviewWaiting: Bool { desiredPreview != nil && previewJob?.request !== desiredPreview }
    public var visibleRecords: [DemoMediaBrowserRecord] {
        Array(current.records.dropFirst(current.pageIndex * Self.pageSize).prefix(Self.pageSize))
    }
    public func thumbnail(for id: String) -> DemoMediaBrowserLoadState { current.thumbnails[id] ?? .idle }

    // The source tests await actual model-owned tasks and inspect demand bounds.
    var activeReadTasks: [Task<Void, Never>] { [previewJob?.task, thumbnailJob?.task].compactMap { $0 } }
    var activeReadCount: Int { activeReadTasks.count }
    var pendingThumbnailIDs: Set<String> { Set(desiredThumbnails.keys) }
    var pendingPreviewID: String? { desiredPreview?.record.id }
    var requestedVisibleIDs: Set<String> { visibleThumbnailIDs }
    var mountedViewID: UUID? { currentMountID }

    private var acceptsActions: Bool { !isClosed && lifetime?.isFinished != true }

    /// Actual root appearance claims one mounted template. A new mount may
    /// replace a disappearing transition overlay that still holds callbacks.
    public func appear(mountID: UUID) {
        guard !isClosed, currentMountID != mountID else { return }
        currentMountID = mountID
        browserVisible = false
        previewVisible = false
        visibleThumbnailIDs.removeAll()
        let previous = lifetime
        lifetime = nil
        let cancelled = revokeLoading()
        previous?.cancel()
        finishMutation(cancelling: cancelled)
    }

    public func disappear(mountID: UUID) {
        guard !isClosed, currentMountID == mountID else { return }
        currentMountID = nil
        browserVisible = false
        previewVisible = false
        visibleThumbnailIDs.removeAll()
        let previous = lifetime
        lifetime = nil
        let cancelled = revokeLoading()
        previous?.cancel()
        finishMutation(cancelling: cancelled)
    }

    /// Mounted by an ordinary public `.task`. Visibility may arrive first, but
    /// no demand can start a read until this live lifetime has entered.
    public func runWhileVisible(mountID: UUID) async {
        let owner = DemoMediaBrowserLifetime()
        await withTaskCancellationHandler {
            guard !Task.isCancelled, !isClosed, currentMountID == mountID, !owner.isFinished else { return }
            let previous = lifetime
            lifetime = owner
            let cancelled = revokeLoading()
            owner.install(activeReadTasks)
            previous?.retire()
            finishMutation(cancelling: cancelled)
            await owner.wait()
        } onCancel: {
            // Revocation and Task.cancel happen before queued MainActor cleanup.
            owner.cancel()
        }
        if lifetime === owner {
            lifetime = nil
            let cancelled = revokeLoading()
            finishMutation(cancelling: cancelled)
        }
    }

    public func setBrowserVisible(_ visible: Bool, mountID: UUID) {
        // Disappearance must still clear staged geometry if task cancellation
        // has already revoked the lifetime but its actor cleanup has not run.
        guard !isClosed, currentMountID == mountID, acceptsActions || !visible,
            browserVisible != visible || (!visible && (previewVisible || !visibleThumbnailIDs.isEmpty))
        else { return }
        browserVisible = visible
        if !visible {
            previewVisible = false
            visibleThumbnailIDs.removeAll()
        }
        finishMutation(cancelling: visible ? [] : revokeLoading())
    }

    public func setPreviewVisible(_ visible: Bool, mountID: UUID) {
        guard !isClosed, currentMountID == mountID, acceptsActions || !visible, previewVisible != visible else {
            return
        }
        previewVisible = visible
        var cancelled: [Task<Void, Never>] = []
        if !visible {
            desiredPreview = nil
            if current.preview.phase == .loading { current.preview = .idle }
            if let job = previewJob { cancelled.append(job.task) }
        }
        finishMutation(cancelling: cancelled)
    }

    public func setThumbnailVisible(id: String, pageScope: UUID, visible: Bool, mountID: UUID) {
        guard !isClosed, currentMountID == mountID, acceptsActions || !visible, pageScope == current.pageScope,
            visibleRecords.contains(where: { $0.id == id })
        else { return }
        let changed = visible ? visibleThumbnailIDs.insert(id).inserted : visibleThumbnailIDs.remove(id) != nil
        guard changed else { return }
        var cancelled: [Task<Void, Never>] = []
        if !visible {
            desiredThumbnails.removeValue(forKey: id)
            if current.thumbnails[id]?.phase == .loading { current.thumbnails[id] = .idle }
            if let job = thumbnailJob, job.request.record.id == id { cancelled.append(job.task) }
        }
        finishMutation(cancelling: cancelled)
    }

    @discardableResult
    public func select(id: String?) -> Bool {
        guard acceptsActions, id != current.selectedID,
            id == nil || current.records.contains(where: { $0.id == id })
        else { return false }
        current.selectedID = id
        current.preview = .idle
        desiredPreview = nil
        finishMutation(cancelling: previewJob.map { [$0.task] } ?? [])
        return true
    }

    public func setLayout(_ layout: DemoMediaBrowserLayout) {
        guard acceptsActions, layout != current.layout else { return }
        current.layout = layout
        let cancelled = replacePage(preservingImages: true)
        finishMutation(cancelling: cancelled)
    }

    @discardableResult
    public func setPage(_ index: Int) -> Bool {
        guard acceptsActions, index >= 0, index < pageCount, index != current.pageIndex else { return false }
        current.pageIndex = index
        let cancelled = replacePage()
        finishMutation(cancelling: cancelled)
        return true
    }

    /// Admission adds a reference, not proof that an image has decoded. The
    /// original URL remains the read/scoped-access capability; identity is lexical.
    @discardableResult
    public func dropFiles(_ urls: [URL]) -> Bool {
        guard acceptsActions else { return false }
        var added: [DemoMediaBrowserRecord] = []
        var ids = Set(current.records.map(\.id))
        for url in urls.prefix(Self.maximumRecordCount) {
            guard current.records.count + added.count < Self.maximumRecordCount else { break }
            guard let identity = try? DemoFilePreviewService.validateFileURL(url) else { continue }
            let id = "file:\(identity.absoluteString)"
            guard ids.insert(id).inserted, let revision = allocateRevision() else { continue }
            added.append(
                DemoMediaBrowserRecord(id: id, name: identity.lastPathComponent, source: .file(url), revision: revision)
            )
        }
        guard let first = added.first else {
            current.notice = "No images added. URLs may be duplicates, unsupported, or beyond the 64-record limit."
            notifyChange()
            return false
        }
        let firstIndex = current.records.count
        current.records.append(contentsOf: added)
        current.selectedID = first.id
        current.pageIndex = firstIndex / Self.pageSize
        current.preview = .idle
        desiredPreview = nil
        let skipped = urls.count - added.count
        current.notice =
            "Added \(added.count) image references."
            + (skipped > 0 ? " Skipped \(skipped) duplicate, unsupported, or excess URLs." : "")
        var cancelled = replacePage()
        if let job = previewJob { cancelled.append(job.task) }
        finishMutation(cancelling: cancelled)
        return true
    }

    @discardableResult
    public func retry(id: String) -> Bool {
        guard acceptsActions, let index = current.records.firstIndex(where: { $0.id == id }) else { return false }
        guard let revision = allocateRevision() else {
            current.notice = "Refresh identifiers are exhausted. Reopen the browser before loading more images."
            notifyChange()
            return false
        }
        current.records[index].revision = revision
        current.notice = nil
        desiredThumbnails.removeValue(forKey: id)
        if current.thumbnails[id] != nil { current.thumbnails[id] = .idle }
        var cancelled: [Task<Void, Never>] = []
        if let job = thumbnailJob, job.request.record.id == id { cancelled.append(job.task) }
        if current.selectedID == id {
            desiredPreview = nil
            current.preview = .idle
            if let job = previewJob { cancelled.append(job.task) }
        }
        finishMutation(cancelling: cancelled)
        return true
    }

    @discardableResult
    public func cancel(id: String) -> Bool {
        guard acceptsActions else { return false }
        var cancelled: [Task<Void, Never>] = []
        var changed = false
        if current.selectedID == id, current.preview.phase == .loading {
            desiredPreview = nil
            current.preview = .cancelled
            if let job = previewJob { cancelled.append(job.task) }
            changed = true
        }
        if current.thumbnails[id]?.phase == .loading {
            desiredThumbnails.removeValue(forKey: id)
            current.thumbnails[id] = .cancelled
            if let job = thumbnailJob, job.request.record.id == id { cancelled.append(job.task) }
            changed = true
        }
        guard changed else { return false }
        finishMutation(cancelling: cancelled)
        return true
    }

    @discardableResult
    public func removeSelected() -> Bool {
        guard acceptsActions, let index = current.records.firstIndex(where: { $0.id == current.selectedID }) else {
            return false
        }
        current.records.remove(at: index)
        let nextIndex = min(index, max(0, current.records.count - 1))
        current.selectedID = current.records.isEmpty ? nil : current.records[nextIndex].id
        current.pageIndex = nextIndex / Self.pageSize
        current.preview = .idle
        current.notice = nil
        desiredPreview = nil
        var cancelled = replacePage()
        if let job = previewJob { cancelled.append(job.task) }
        finishMutation(cancelling: cancelled)
        return true
    }

    public func clear() {
        guard acceptsActions else { return }
        current.records = []
        current.selectedID = nil
        current.pageIndex = 0
        current.preview = .idle
        current.notice = nil
        desiredPreview = nil
        var cancelled = replacePage()
        if let job = previewJob { cancelled.append(job.task) }
        finishMutation(cancelling: cancelled)
    }

    public func restoreSamples() {
        guard acceptsActions else { return }
        current.records = DemoMediaBrowserRecord.samples
        current.selectedID = current.records.first?.id
        current.pageIndex = 0
        current.preview = .idle
        current.notice = "Restored two real PNG samples and two encoded inputs that fail decoding."
        desiredPreview = nil
        var cancelled = replacePage()
        if let job = previewJob { cancelled.append(job.task) }
        finishMutation(cancelling: cancelled)
    }

    /// Revokes admission synchronously, including before a queued view task
    /// enters. One retained cleanup task closes the service; occupied lanes
    /// still remain until their cancelled service calls actually return.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        currentMountID = nil
        browserVisible = false
        previewVisible = false
        visibleThumbnailIDs.removeAll()
        desiredPreview = nil
        desiredThumbnails.removeAll()
        current.thumbnails.removeAll()
        current.preview = current.selectedID == nil ? .idle : .cancelled
        let owner = lifetime
        lifetime = nil
        let tasks = activeReadTasks
        let service = service
        shutdownTask = Task { await service.close() }
        owner?.cancel()
        for task in tasks { task.cancel() }
        notifyChange()
    }

    public func awaitServiceClose() async { await shutdownTask?.value }

    private func allocateRevision() -> UInt64? {
        guard let revision = nextRevision else { return nil }
        nextRevision = revision == UInt64.max ? nil : revision + 1
        return revision
    }

    private func replacePage(preservingImages: Bool = false) -> [Task<Void, Never>] {
        current.pageScope = UUID()
        visibleThumbnailIDs.removeAll()
        desiredThumbnails.removeAll()
        let previous = current.thumbnails
        current.thumbnails = Dictionary(
            uniqueKeysWithValues: visibleRecords.map { record in
                let state = previous[record.id] ?? .idle
                return (record.id, preservingImages && state.phase != .loading ? state : .idle)
            })
        return thumbnailJob.map { [$0.task] } ?? []
    }

    private func revokeLoading() -> [Task<Void, Never>] {
        desiredPreview = nil
        desiredThumbnails.removeAll()
        if current.preview.phase == .loading { current.preview = .idle }
        for id in Array(current.thumbnails.keys) where current.thumbnails[id]?.phase == .loading {
            current.thumbnails[id] = .idle
        }
        return activeReadTasks
    }

    private func finishMutation(cancelling tasks: [Task<Void, Never>]) {
        // All authority/state changes precede cancellation callouts. Reentry may
        // replace intent again, so pump reads the current state after they return.
        for task in tasks { task.cancel() }
        pump()
        if acceptsActions { notifyChange() }
    }

    private func pump() {
        guard isActive, let owner = lifetime, !owner.isFinished else { return }
        if previewVisible, let record = selectedRecord, current.preview.phase == .idle {
            desiredPreview = DemoMediaBrowserRequest(record: record, kind: .preview, pageScope: current.pageScope)
            current.preview = .loading
        }
        for record in visibleRecords where visibleThumbnailIDs.contains(record.id) {
            if current.thumbnails[record.id]?.phase == .idle {
                desiredThumbnails[record.id] = DemoMediaBrowserRequest(
                    record: record, kind: .thumbnail, pageScope: current.pageScope)
                current.thumbnails[record.id] = .loading
            }
        }
        if previewJob == nil, let request = desiredPreview { start(request, owner: owner) }
        if thumbnailJob == nil,
            let request = visibleRecords.compactMap({ desiredThumbnails[$0.id] }).first
        {
            start(request, owner: owner)
        }
    }

    private func start(_ request: DemoMediaBrowserRequest, owner: DemoMediaBrowserLifetime) {
        let service = service
        let task = Task { @MainActor [weak self] in
            let result: Result<DemoMediaImage, Error>
            do {
                try Task.checkCancellation()
                guard self?.isCurrent(request, owner: owner) == true else { throw CancellationError() }
                let edge = request.kind == .preview ? Self.previewPixelDimension : Self.thumbnailPixelDimension
                let image = try await service.load(
                    request.record.source, maximumPixelDimension: edge, revision: request.record.revision)
                try Task.checkCancellation()
                result = .success(image)
            } catch { result = .failure(error) }
            self?.finish(request, owner: owner, result: result)
        }
        let job = DemoMediaBrowserJob(request: request, task: task)
        if request.kind == .preview { previewJob = job } else { thumbnailJob = job }
        owner.install(activeReadTasks)
    }

    private func isCurrent(_ request: DemoMediaBrowserRequest, owner: DemoMediaBrowserLifetime) -> Bool {
        guard isActive, lifetime === owner, !owner.isFinished,
            current.records.contains(where: { $0.id == request.record.id && $0.revision == request.record.revision })
        else { return false }
        switch request.kind {
        case .preview:
            return previewVisible && current.selectedID == request.record.id && desiredPreview === request
        case .thumbnail:
            return request.pageScope == current.pageScope && visibleThumbnailIDs.contains(request.record.id)
                && desiredThumbnails[request.record.id] === request
        }
    }

    private func finish(
        _ request: DemoMediaBrowserRequest, owner: DemoMediaBrowserLifetime, result: Result<DemoMediaImage, Error>
    ) {
        if request.kind == .preview {
            guard previewJob?.request === request else { return }
            previewJob = nil
        } else {
            guard thumbnailJob?.request === request else { return }
            thumbnailJob = nil
        }
        lifetime?.install(activeReadTasks)
        let state: DemoMediaBrowserLoadState
        switch result {
        case .success(let image): state = .ready(image)
        case .failure(is CancellationError): state = .cancelled
        case .failure(let error): state = .failed(error.localizedDescription)
        }
        // Error descriptions are application callouts too. Recheck current
        // attempt, source, visibility, selection and lifetime after formatting.
        if isCurrent(request, owner: owner) {
            if request.kind == .preview {
                desiredPreview = nil
                current.preview = state
            } else {
                desiredThumbnails.removeValue(forKey: request.record.id)
                current.thumbnails[request.record.id] = state
            }
        }
        pump()
        if acceptsActions { notifyChange() }
    }

    private func notifyChange() { changeSignal &+= 1 }
}

private final class DemoMediaBrowserRequest: Sendable {
    enum Kind: Equatable, Sendable { case preview, thumbnail }
    let record: DemoMediaBrowserRecord
    let kind: Kind
    let pageScope: UUID

    init(record: DemoMediaBrowserRecord, kind: Kind, pageScope: UUID) {
        self.record = record
        self.kind = kind
        self.pageScope = pageScope
    }
}

@MainActor
private struct DemoMediaBrowserJob {
    let request: DemoMediaBrowserRequest
    let task: Task<Void, Never>
}

/// Only the finished bit, two task handles and one waiter live behind this lock.
/// Cancellation, releases and continuation resumes happen after unlocking.
private final class DemoMediaBrowserLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var tasks: [Task<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func install(_ active: [Task<Void, Never>]) {
        lock.lock()
        let reject = finished
        let previous = tasks
        if !reject { tasks = active }
        lock.unlock()
        withExtendedLifetime(previous) {}
        if reject {
            for task in active { task.cancel() }
        }
    }

    func wait() async {
        await withCheckedContinuation { waiting in
            lock.lock()
            let resumeImmediately = finished
            if !resumeImmediately { continuation = waiting }
            lock.unlock()
            if resumeImmediately { waiting.resume() }
        }
    }

    func cancel() { finish(cancelTasks: true) }
    func retire() { finish(cancelTasks: false) }

    private func finish(cancelTasks: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let waiting = continuation
        let active = tasks
        continuation = nil
        tasks = []
        lock.unlock()
        if cancelTasks {
            for task in active { task.cancel() }
        }
        waiting?.resume()
    }
}
