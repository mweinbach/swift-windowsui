import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// A caller-owned, read-only media workflow. Paging bounds construction before
/// either collection receives data. Geometry visibility bounds thumbnail and
/// preview demand; it is not an OS window-occlusion or codec-preemption claim.
@MainActor
public struct DemoMediaBrowserTemplate: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var model: DemoMediaBrowserModel
    @StateObject private var mount = DemoMediaBrowserMount()

    public init(model: DemoMediaBrowserModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }
    private var selection: Binding<String?> {
        Binding(get: { model.selectedID }, set: { _ = model.select(id: $0) })
    }

    public var body: some View {
        // Resolve the installed StateObject now, not from a later callback's
        // copied wrapper. A reused authored view gets a fresh object per mount.
        let mountedOwner = mount
        let mountID = mountedOwner.id
        return GeometryReader { geometry in
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                    Text("Media browser")
                        .font(DemoType.section)
                        .accessibilityAddTraits(.isHeader)
                    Text("Drop PNG, JPEG or BMP files. Samples use the same image decoder.")
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: DemoMetrics.s2) {
                    Button("Grid") { model.setLayout(.grid) }
                        .accessibilityIdentifier("media.browser.grid")
                        .disabled(model.layout == .grid || model.isClosed)
                    Button("List") { model.setLayout(.list) }
                        .accessibilityIdentifier("media.browser.list")
                        .disabled(model.layout == .list || model.isClosed)
                    Spacer(minLength: 0)
                    Button("Samples") { model.restoreSamples() }
                        .accessibilityIdentifier("media.browser.samples")
                        .disabled(model.isClosed)
                    Button("Clear") { model.clear() }
                        .accessibilityIdentifier("media.browser.clear")
                        .disabled(model.records.isEmpty || model.isClosed)
                }
                .buttonStyle(.bordered)

                if let notice = model.notice {
                    Text(notice)
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("media.browser.notice")
                }

                // The inner scroll view gives standalone native SwiftUI the
                // same visibility ancestor as the gallery composition. Each
                // image well also observes the clip from an outer gallery.
                ScrollView {
                    Group {
                        if geometry.size.width < 700 {
                            VStack(alignment: .leading, spacing: DemoMetrics.s4) {
                                collection(mountID: mountID)
                                previewPane(mountID: mountID)
                            }
                        } else {
                            HStack(alignment: .top, spacing: DemoMetrics.s4) {
                                collection(mountID: mountID).frame(maxWidth: .infinity, alignment: .topLeading)
                                previewPane(mountID: mountID).frame(width: min(360, geometry.size.width * 0.43))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onScrollVisibilityChange(threshold: 0) { model.setBrowserVisible($0, mountID: mountID) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityIdentifier("media.browser.viewport")

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "\(model.records.count)/\(DemoMediaBrowserModel.maximumRecordCount) image references · 4 per page"
                    )
                    .accessibilityIdentifier("media.browser.count")
                    Text("Read only · 8 MiB per file · 16 million source pixels")
                }
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .padding(DemoMetrics.s4)
        .frame(minHeight: 560)
        .background(palette.surface1)
        .cornerRadius(DemoMetrics.radiusMD)
        .accessibilityIdentifier("media.browser")
        .onAppear {
            model.appear(mountID: mountID)
            mountedOwner.appearance.enter()
        }
        .task { @MainActor in
            guard await mountedOwner.appearance.waitUntilEntered() else { return }
            await model.runWhileVisible(mountID: mountID)
        }
        .onDisappear {
            model.disappear(mountID: mountID)
            mountedOwner.appearance.leave()
        }
        .dropDestination(for: URL.self) { urls, _ in model.dropFiles(urls) }
    }

    private func collection(mountID: UUID) -> some View {
        let scope = model.pageScope
        let page = model.visibleRecords
        return VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            HStack {
                Text("Images").font(DemoType.cardTitle)
                Spacer(minLength: 0)
                Button("Remove") { _ = model.removeSelected() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("media.browser.remove")
                    .disabled(model.selectedID == nil || model.isClosed)
            }

            Group {
                if page.isEmpty {
                    VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                        Text("No images").font(DemoType.body)
                        Text("Drop files here or restore the built-in samples.")
                            .font(DemoType.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .accessibilityIdentifier("media.browser.empty")
                } else if model.layout == .grid {
                    // LazyVGrid currently constructs supplied content eagerly
                    // on Windows. Only this finite page ever reaches ForEach.
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8
                    ) {
                        ForEach(page) { record in gridCard(record, scope: scope, mountID: mountID) }
                    }
                } else {
                    List(page, selection: selection) { record in
                        listRow(record, scope: scope, mountID: mountID).id(record.id)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: 376)
                }
            }
            // Observer reconciliation retains its delivered value. A new
            // page/layout gets fresh owners even when its geometry is equal.
            .id(scope)

            HStack(spacing: DemoMetrics.s2) {
                Button("Previous") { _ = model.setPage(model.pageIndex - 1) }
                    .accessibilityIdentifier("media.browser.previous")
                    .disabled(model.pageIndex == 0 || model.isClosed)
                Spacer(minLength: 0)
                Text("Page \(model.pageIndex + 1) of \(model.pageCount)")
                    .font(DemoType.caption)
                    .accessibilityIdentifier("media.browser.page")
                Spacer(minLength: 0)
                Button("Next") { _ = model.setPage(model.pageIndex + 1) }
                    .accessibilityIdentifier("media.browser.next")
                    .disabled(model.pageIndex + 1 >= model.pageCount || model.isClosed)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func gridCard(_ record: DemoMediaBrowserRecord, scope: UUID, mountID: UUID) -> some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            Button {
                _ = model.select(id: record.id)
            } label: {
                VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                    thumbnail(record, scope: scope, height: 88, mountID: mountID)
                    Text(record.name).font(DemoType.caption).lineLimit(1)
                    Text(record.sourceDescription).font(DemoType.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(record.name)")
            .accessibilityIdentifier("media.browser.select.\(record.id)")
            .disabled(model.isClosed)

            thumbnailActions(record)
        }
        .padding(DemoMetrics.s2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(model.selectedID == record.id ? palette.surface3 : palette.surface2)
        .cornerRadius(DemoMetrics.radiusSM)
        .accessibilityIdentifier("media.browser.record.\(record.id)")
    }

    private func listRow(_ record: DemoMediaBrowserRecord, scope: UUID, mountID: UUID) -> some View {
        HStack(spacing: DemoMetrics.s2) {
            thumbnail(record, scope: scope, height: 64, mountID: mountID).frame(width: 72)
            VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                Text(record.name).font(DemoType.caption).lineLimit(1)
                Text(record.sourceDescription).font(DemoType.caption).foregroundStyle(.secondary).lineLimit(1)
                thumbnailActions(record)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .accessibilityLabel("\(record.name), \(record.sourceDescription)")
        .accessibilityIdentifier("media.browser.record.\(record.id)")
    }

    private func thumbnail(_ record: DemoMediaBrowserRecord, scope: UUID, height: CGFloat, mountID: UUID) -> some View {
        imageWell(
            model.thumbnail(for: record.id), name: record.name, identifier: "media.browser.thumbnail.\(record.id)",
            compact: true, waiting: false
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(palette.surface0)
        .clipped()
        .onScrollVisibilityChange(threshold: 0) {
            model.setThumbnailVisible(id: record.id, pageScope: scope, visible: $0, mountID: mountID)
        }
        .onDisappear { model.setThumbnailVisible(id: record.id, pageScope: scope, visible: false, mountID: mountID) }
    }

    private func thumbnailActions(_ record: DemoMediaBrowserRecord) -> some View {
        HStack(spacing: DemoMetrics.s1) {
            Button("Retry") { _ = model.retry(id: record.id) }
                .accessibilityIdentifier("media.browser.thumbnail.retry.\(record.id)")
                .disabled(model.thumbnail(for: record.id).phase == .loading || model.isClosed)
            Button("Cancel") { _ = model.cancel(id: record.id) }
                .accessibilityIdentifier("media.browser.thumbnail.cancel.\(record.id)")
                .disabled(model.thumbnail(for: record.id).phase != .loading || model.isClosed)
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
    }

    private func previewPane(mountID: UUID) -> some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            Text(model.selectedRecord?.name ?? "Preview")
                .font(DemoType.cardTitle)
                .lineLimit(1)
                .accessibilityIdentifier("media.browser.preview.name")

            HStack(spacing: DemoMetrics.s2) {
                Button("Retry") {
                    if let id = model.selectedID { _ = model.retry(id: id) }
                }
                .accessibilityIdentifier("media.browser.preview.retry")
                .disabled(model.selectedID == nil || model.preview.phase == .loading || model.isClosed)
                Button("Cancel") {
                    if let id = model.selectedID { _ = model.cancel(id: id) }
                }
                .accessibilityIdentifier("media.browser.preview.cancel")
                .disabled(model.preview.phase != .loading || model.isClosed)
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)

            imageWell(
                model.preview, name: model.selectedRecord?.name ?? "Preview", identifier: "media.browser.preview",
                compact: false, waiting: model.isPreviewWaiting
            )
            .frame(maxWidth: .infinity)
            .frame(height: 284)
            .background(palette.surface0)
            .cornerRadius(DemoMetrics.radiusSM)
            .clipped()
            .onScrollVisibilityChange(threshold: 0) { model.setPreviewVisible($0, mountID: mountID) }
            .onDisappear { model.setPreviewVisible(false, mountID: mountID) }

            if case .ready(let image) = model.preview {
                Text(
                    "\(image.sourcePixelWidth) × \(image.sourcePixelHeight) source · \(image.pixelWidth) × \(image.pixelHeight) preview"
                )
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("media.browser.preview.dimensions")
            }
            Text("Selection stays with the image when the page or layout changes.")
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func imageWell(
        _ state: DemoMediaBrowserLoadState, name: String, identifier: String, compact: Bool, waiting: Bool
    ) -> some View {
        switch state {
        case .idle:
            Text(compact ? "Not loaded" : "Select an image. Only visible image wells start loading.")
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifier).idle")
        case .loading:
            VStack(spacing: DemoMetrics.s1) {
                ProgressView().accessibilityLabel("Loading \(name)")
                Text(waiting ? "Waiting for the previous read…" : "Loading…")
                    .font(DemoType.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("\(identifier).loading")
        case .ready(let image):
            image.image.resizable().scaledToFit()
                .accessibilityLabel(name)
                .accessibilityIdentifier("\(identifier).ready")
        case .failed(let message):
            VStack(spacing: DemoMetrics.s1) {
                Text("Image unavailable").font(DemoType.caption)
                if !compact {
                    Text(message).font(DemoType.caption).foregroundStyle(.secondary)
                    Text("Retry reads the same source again.").font(DemoType.caption).foregroundStyle(.secondary)
                }
            }
            .padding(DemoMetrics.s2)
            .accessibilityLabel("\(name): \(message)")
            .accessibilityIdentifier("\(identifier).failed")
        case .cancelled:
            Text(compact ? "Cancelled" : "Preview cancelled. Retry to load it again.")
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifier).cancelled")
        }
    }
}

/// StateObject retains this factory result across rebuilds, but calls the
/// factory again for a new mount even when the authored template value is reused.
@MainActor
private final class DemoMediaBrowserMount: ObservableObject {
    let id = UUID()
    let appearance = DemoMediaBrowserAppearance()
}

/// One appearance bit and at most one pending view-task waiter. This avoids
/// assuming a platform's task/onAppear order. No decoding or UI work is owned
/// here, and continuation resumes/releases occur after unlocking.
private final class DemoMediaBrowserAppearance: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private var pending: DemoMediaBrowserAppearanceWait?

    func enter() { setEntered(true) }
    func leave() { setEntered(false) }

    @MainActor func waitUntilEntered() async -> Bool {
        let waiter = DemoMediaBrowserAppearanceWait()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            install(waiter)
            let entered = await waiter.value()
            remove(waiter)
            return entered && !Task.isCancelled
        } onCancel: {
            // The waiter remembers cancellation before installation too.
            waiter.finish(false)
            self.remove(waiter)
        }
    }

    private func install(_ waiter: DemoMediaBrowserAppearanceWait) {
        lock.lock()
        let previous = pending
        let ready = entered
        pending = ready ? nil : waiter
        lock.unlock()
        previous?.finish(false)
        if ready { waiter.finish(true) }
    }

    private func remove(_ waiter: DemoMediaBrowserAppearanceWait) {
        lock.lock()
        let previous = pending
        if pending === waiter { pending = nil }
        lock.unlock()
        withExtendedLifetime(previous) {}
    }

    private func setEntered(_ entered: Bool) {
        lock.lock()
        self.entered = entered
        let waiter = pending
        pending = nil
        lock.unlock()
        waiter?.finish(entered)
    }
}

private final class DemoMediaBrowserAppearanceWait: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    func value() async -> Bool {
        await withCheckedContinuation { waiting in
            lock.lock()
            let completedResult = result
            if completedResult == nil { continuation = waiting }
            lock.unlock()
            if let completedResult { waiting.resume(returning: completedResult) }
        }
    }

    func finish(_ result: Bool) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: result)
    }
}
