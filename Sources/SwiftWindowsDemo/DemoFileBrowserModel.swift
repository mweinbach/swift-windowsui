import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

public struct DemoFileBrowserRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let source: DemoFilePreviewSource

    public var sourceDescription: String {
        switch source {
        case .file: return "Local file"
        case .sample: return "Built-in sample"
        }
    }

    public static var samples: [Self] {
        [
            Self(
                id: "sample:welcome", name: "Welcome.txt",
                source: .sample(
                    Data(
                        """
                        Local file preview

                        Import or drop a UTF-8 text file, then select it in the list.
                        The preview reads the file without changing it.

                        Cancel stops further work. Retry reads the selected source again.
                        Files larger than 64 KiB are rejected, not silently truncated.
                        """.utf8))),
            Self(
                id: "sample:unicode", name: "Unicode.txt",
                source: .sample(Data("Café · cafe\u{301} · 日本語 · 👩🏽‍💻\r\nSecond line\n".utf8))),
            Self(id: "sample:empty", name: "Empty.txt", source: .sample(Data())),
            Self(
                id: "sample:invalid", name: "Invalid UTF-8.txt",
                source: .sample(Data([0xC3, 0x28]))),
        ]
    }
}

public enum DemoFileBrowserPreviewState: Equatable, Sendable {
    case idle
    case loading
    case ready(DemoFilePreview)
    case failed(String)
    case cancelled
}

public struct DemoFileBrowserSnapshot: Equatable, Sendable {
    public fileprivate(set) var records: [DemoFileBrowserRecord]
    public fileprivate(set) var selectedID: String?
    public fileprivate(set) var preview: DemoFileBrowserPreviewState
    public fileprivate(set) var importNotice: String?
    public fileprivate(set) var isImporterPresented: Bool
}

/// One window owns its file list and at most one active preview read. Cancellation
/// keeps that read's slot until it returns; only the latest pending request waits.
@MainActor
public final class DemoFileBrowserModel: ObservableObject {
    public static let maximumFileCount = 64

    // The snapshot is authoritative before notification. The private signal is
    // not a request ID: nested synchronous publication cannot roll state back.
    @Published private var changeSignal: UInt = 0
    private var current: DemoFileBrowserSnapshot
    private let service: DemoFilePreviewService
    private var worker: Task<Void, Never>?
    private var activeRequest: DemoFileBrowserRequest?
    private var pendingRequest: DemoFileBrowserRequest?
    private var desiredRequest: DemoFileBrowserRequest?
    // Public actions before the view's queued lifecycle task first runs may
    // update intent, but cannot start I/O. Non-view clients explicitly resume.
    private var isSuspended = true
    private var shouldResumePreview = true
    private var mutation = DemoFileBrowserMutation()
    private var viewLifetime: DemoFileBrowserViewLifetime?
    public private(set) var isClosed = false

    public init(service: DemoFilePreviewService = .localFiles, includesSamples: Bool = true) {
        self.service = service
        let records = includesSamples ? DemoFileBrowserRecord.samples : []
        current = DemoFileBrowserSnapshot(
            records: records, selectedID: records.first?.id, preview: .idle,
            importNotice: nil, isImporterPresented: false)
    }

    isolated deinit {
        worker?.cancel()
        viewLifetime?.cancel()
    }

    public var snapshot: DemoFileBrowserSnapshot { current }
    public var records: [DemoFileBrowserRecord] { current.records }
    public var selectedID: String? { current.selectedID }
    public var preview: DemoFileBrowserPreviewState { current.preview }
    public var importNotice: String? { current.importNotice }
    public var isImporterPresented: Bool { current.isImporterPresented }
    public var isActive: Bool { acceptsReadCompletion }
    public var isReading: Bool { worker != nil }
    public var isWaitingForPreviousRead: Bool { worker != nil && pendingRequest != nil }
    public var selectedRecord: DemoFileBrowserRecord? {
        current.records.first { $0.id == current.selectedID }
    }

    // Source tests inspect scheduler ownership, not inferred phase labels.
    var activeReadCount: Int { worker == nil ? 0 : 1 }
    var activeReadTask: Task<Void, Never>? { worker }
    var pendingReadID: String? { pendingRequest?.record.id }

    private var acceptsNewActions: Bool { !isClosed && viewLifetime?.isFinished != true }
    private var acceptsReadCompletion: Bool { acceptsNewActions && !isSuspended }

    /// Awaited by an ordinary SwiftUI `.task`, whose retained owner is cancelled
    /// on removal and window teardown even when disappearance callbacks stop.
    public func runWhileVisible() async {
        let lifetime = DemoFileBrowserViewLifetime()
        await withTaskCancellationHandler {
            guard !Task.isCancelled, !isClosed, !lifetime.isFinished else { return }
            let previous = viewLifetime
            viewLifetime = lifetime
            lifetime.installWorker(worker)
            previous?.retire()
            // A new mount supersedes old visibility authority. Its predecessor
            // may already have cancelled the shared physical read; resume a new
            // request only after that read drains.
            if previous != nil { suspend() }
            if !Task.isCancelled, !lifetime.isFinished, viewLifetime === lifetime { resume() }
            await lifetime.wait()
        } onCancel: {
            // This is synchronous and thread-safe. A queued completion cannot
            // publish or start pending work before MainActor cleanup runs.
            lifetime.cancel()
        }
        if viewLifetime === lifetime {
            viewLifetime = nil
            suspend()
        }
    }

    @discardableResult
    public func select(id: String?) -> Bool {
        guard acceptsNewActions, id != current.selectedID else { return false }
        guard id == nil || current.records.contains(where: { $0.id == id }) else { return false }
        mutation = DemoFileBrowserMutation()
        current.selectedID = id
        prepareSelectedPreview()
        notifyChange()
        return true
    }

    /// Lexical admission does not claim that a file has been opened or decoded.
    /// The selected preview reports missing, nonregular, oversized and invalid data.
    @discardableResult
    public func importFiles(_ urls: [URL]) -> Bool {
        guard acceptsNewActions else { return false }
        mutation = DemoFileBrowserMutation()
        let accepted = appendFiles(urls)
        notifyChange()
        return accepted
    }

    public func setImporterPresented(_ presented: Bool) {
        guard acceptsNewActions, !isSuspended, presented != current.isImporterPresented else { return }
        mutation = DemoFileBrowserMutation()
        current.isImporterPresented = presented
        notifyChange()
    }

    public func receiveImportResult(_ result: Result<[URL], Error>) {
        guard acceptsNewActions, !isSuspended else { return }
        let capturedMutation = mutation
        // The current facade's cancellation error is opaque. Do not inspect its
        // private type name or report every failure callback as cancellation.
        let failureDescription: String?
        switch result {
        case .success: failureDescription = nil
        case .failure(let error): failureDescription = error.localizedDescription
        }
        guard acceptsNewActions, !isSuspended, mutation === capturedMutation else { return }
        mutation = DemoFileBrowserMutation()
        current.isImporterPresented = false
        switch result {
        case .success(let urls):
            _ = appendFiles(urls)
        case .failure:
            current.importNotice = "Import was not completed: \(failureDescription ?? "No files were added.")"
        }
        notifyChange()
    }

    @discardableResult
    public func retryPreview() -> Bool {
        guard acceptsNewActions, selectedRecord != nil else { return false }
        mutation = DemoFileBrowserMutation()
        prepareSelectedPreview()
        notifyChange()
        return true
    }

    @discardableResult
    public func cancelPreview() -> Bool {
        guard !isClosed,
            desiredRequest != nil || pendingRequest != nil || (shouldResumePreview && selectedRecord != nil)
        else { return false }
        mutation = DemoFileBrowserMutation()
        desiredRequest = nil
        pendingRequest = nil
        shouldResumePreview = false
        current.preview = .cancelled
        // Commit cancellation authority before a cancellation handler can reenter.
        worker?.cancel()
        notifyChange()
        return true
    }

    @discardableResult
    public func removeSelectedFile() -> Bool {
        guard acceptsNewActions,
            let index = current.records.firstIndex(where: { $0.id == current.selectedID })
        else { return false }
        mutation = DemoFileBrowserMutation()
        current.records.remove(at: index)
        current.selectedID =
            current.records.isEmpty ? nil : current.records[min(index, current.records.count - 1)].id
        current.importNotice = nil
        prepareSelectedPreview()
        notifyChange()
        return true
    }

    public func clearFiles() {
        guard acceptsNewActions else { return }
        mutation = DemoFileBrowserMutation()
        current.records = []
        current.selectedID = nil
        current.importNotice = nil
        current.isImporterPresented = false
        prepareSelectedPreview()
        notifyChange()
    }

    public func restoreSamples() {
        guard acceptsNewActions else { return }
        mutation = DemoFileBrowserMutation()
        current.records = DemoFileBrowserRecord.samples
        current.selectedID = current.records.first?.id
        current.importNotice = "Restored the four built-in samples. No files were changed."
        current.isImporterPresented = false
        prepareSelectedPreview()
        notifyChange()
    }

    /// Appearance resumes a suspended read, but never silently retries a user's
    /// Cancel or a failed decode. Constructing the model does not perform I/O.
    public func resume() {
        guard acceptsNewActions else { return }
        let wasSuspended = isSuspended
        guard wasSuspended || shouldResumePreview else { return }
        mutation = DemoFileBrowserMutation()
        isSuspended = false
        if shouldResumePreview {
            prepareSelectedPreview()
            notifyChange()
        } else if wasSuspended {
            notifyChange()
        }
    }

    public func suspend() {
        guard !isClosed, !isSuspended else { return }
        mutation = DemoFileBrowserMutation()
        isSuspended = true
        current.isImporterPresented = false
        shouldResumePreview = shouldResumePreview || desiredRequest != nil || pendingRequest != nil
        desiredRequest = nil
        pendingRequest = nil
        if current.preview == .loading { current.preview = .cancelled }
        worker?.cancel()
        notifyChange()
    }

    /// Terminal owner teardown. Reopening a browser requires a new model.
    public func close() {
        guard !isClosed else { return }
        mutation = DemoFileBrowserMutation()
        isClosed = true
        isSuspended = true
        shouldResumePreview = false
        desiredRequest = nil
        pendingRequest = nil
        current.isImporterPresented = false
        if current.preview == .loading { current.preview = .cancelled }
        let lifetime = viewLifetime
        viewLifetime = nil
        worker?.cancel()
        lifetime?.cancel()
        notifyChange()
    }

    private func appendFiles(_ urls: [URL]) -> Bool {
        var added: [DemoFileBrowserRecord] = []
        var ids = Set(current.records.map(\.id))
        // Bound admission work as well as retained records for a very large drop.
        for url in urls.prefix(Self.maximumFileCount) {
            guard current.records.count + added.count < Self.maximumFileCount else { break }
            guard let normalized = try? DemoFilePreviewService.validateFileURL(url) else { continue }
            let id = "file:\(normalized.absoluteString)"
            guard ids.insert(id).inserted else { continue }
            added.append(DemoFileBrowserRecord(id: id, name: normalized.lastPathComponent, source: .file(url)))
        }
        current.records.append(contentsOf: added)
        let skipped = urls.count - added.count
        if added.isEmpty {
            current.importNotice =
                "No files were added. Items may be duplicates, unsupported URLs, or beyond the 64-file limit."
        } else {
            current.importNotice =
                "Added \(added.count) \(added.count == 1 ? "file" : "files") to the list."
                + (skipped == 0 ? "" : " Skipped \(skipped) duplicate, unsupported, or excess items.")
            current.selectedID = added[0].id
            prepareSelectedPreview()
        }
        return !added.isEmpty
    }

    private func prepareSelectedPreview() {
        desiredRequest = nil
        pendingRequest = nil
        shouldResumePreview = false
        if let record = selectedRecord {
            if !acceptsReadCompletion {
                current.preview = .idle
                shouldResumePreview = true
            } else {
                let request = DemoFileBrowserRequest(record: record)
                desiredRequest = request
                pendingRequest = request
                current.preview = .loading
            }
        } else {
            current.preview = .idle
        }
        // Do not clear worker here: even cancelled blocking I/O owns its slot.
        worker?.cancel()
        // A cancellation handler can reenter; start only the CURRENT pending work.
        startPendingWorkIfPossible()
    }

    private func startPendingWorkIfPossible() {
        guard acceptsReadCompletion, worker == nil, let request = pendingRequest,
            desiredRequest === request, current.selectedID == request.record.id
        else { return }
        pendingRequest = nil
        activeRequest = request
        let service = service
        worker = Task { @MainActor [weak self] in
            let result: Result<DemoFilePreview, Error>
            do {
                let preview = try await service.load(request.record.source)
                try Task.checkCancellation()
                result = .success(preview)
            } catch {
                result = .failure(error)
            }
            self?.finish(request, result: result)
        }
        viewLifetime?.installWorker(worker)
    }

    private func finish(_ request: DemoFileBrowserRequest, result: Result<DemoFilePreview, Error>) {
        guard activeRequest === request else { return }
        mutation = DemoFileBrowserMutation()
        worker = nil
        activeRequest = nil
        viewLifetime?.installWorker(nil)
        let phase: DemoFileBrowserPreviewState
        switch result {
        case .success(let preview): phase = .ready(preview)
        case .failure(is CancellationError): phase = .cancelled
        case .failure(let error): phase = .failed(error.localizedDescription)
        }
        // Error formatting is application code too: recheck authority after it.
        if acceptsReadCompletion, desiredRequest === request, current.selectedID == request.record.id {
            current.preview = phase
            desiredRequest = nil
        }
        startPendingWorkIfPossible()
        if acceptsNewActions { notifyChange() }
    }

    private func notifyChange() {
        changeSignal &+= 1
    }
}

private final class DemoFileBrowserRequest: Sendable {
    let record: DemoFileBrowserRecord

    init(record: DemoFileBrowserRecord) {
        self.record = record
    }
}

private final class DemoFileBrowserMutation: Sendable {}

/// All fields are protected by the lock. The cancellation callback may run on a
/// non-UI thread; it only revokes this lease and cancels a Sendable task handle.
private final class DemoFileBrowserViewLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var worker: Task<Void, Never>?

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func installWorker(_ task: Task<Void, Never>?) {
        lock.lock()
        let reject = finished
        if !reject { worker = task }
        lock.unlock()
        if reject { task?.cancel() }
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

    func cancel() { finish(cancelWorker: true) }
    func retire() { finish(cancelWorker: false) }

    private func finish(cancelWorker: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let waiting = continuation
        let running = cancelWorker ? worker : nil
        continuation = nil
        worker = nil
        lock.unlock()
        running?.cancel()
        waiting?.resume()
    }
}
