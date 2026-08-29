import Foundation

#if canImport(SwiftUI)
    import SwiftUI
    import UniformTypeIdentifiers
#else
    import WinSwiftUI
#endif

/// A read-only UTF-8 file browser. The caller owns its model; the gallery gives
/// each window a separate instance. Images and outgoing drag sessions are not
/// implemented by this text-preview slice.
@MainActor
public struct DemoFileBrowserTemplate: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var model: DemoFileBrowserModel

    public init(model: DemoFileBrowserModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }
    private var selection: Binding<String?> {
        Binding(get: { model.selectedID }, set: { _ = model.select(id: $0) })
    }
    private var importerPresented: Binding<Bool> {
        Binding(get: { model.isImporterPresented }, set: { model.setImporterPresented($0) })
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                    Text("Local file browser")
                        .font(DemoType.section)
                        .accessibilityAddTraits(.isHeader)
                    Text("Import or drop UTF-8 files for a read-only preview")
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: DemoMetrics.s2) {
                    DemoButton("Import…") { model.setImporterPresented(true) }
                        .accessibilityIdentifier("file.browser.import")
                        .disabled(!model.isActive)
                    DemoButton("Samples") { model.restoreSamples() }
                        .accessibilityIdentifier("file.browser.samples")
                        .disabled(model.isClosed)
                    DemoButton("Clear") { model.clearFiles() }
                        .accessibilityIdentifier("file.browser.clear")
                        .disabled(model.records.isEmpty || model.isClosed)
                    Spacer(minLength: 0)
                }

                if let notice = model.importNotice {
                    Text(notice)
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("file.browser.import.notice")
                }

                if geometry.size.width < 600 {
                    VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                        fileList
                            .frame(height: min(156, max(104, geometry.size.height * 0.3)))
                        previewPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    HStack(alignment: .top, spacing: DemoMetrics.s4) {
                        fileList.frame(width: 210)
                        previewPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                HStack {
                    Text("\(model.records.count)/\(DemoFileBrowserModel.maximumFileCount) files")
                        .accessibilityIdentifier("file.browser.count")
                    Spacer(minLength: 0)
                    Text("Read only · 64 KiB limit")
                }
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .padding(DemoMetrics.s4)
        .frame(minHeight: 420)
        .background(palette.surface1)
        .cornerRadius(DemoMetrics.radiusMD)
        .accessibilityIdentifier("file.browser")
        .task { @MainActor in await model.runWhileVisible() }
        .fileImporter(
            isPresented: importerPresented,
            allowedContentTypes: [.utf8PlainText],
            allowsMultipleSelection: true
        ) { result in
            model.receiveImportResult(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls)
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            HStack {
                Text("Files").font(DemoType.cardTitle)
                Spacer(minLength: 0)
                DemoButton("Remove") { _ = model.removeSelectedFile() }
                    .accessibilityIdentifier("file.browser.remove")
                    .disabled(model.selectedID == nil || model.isClosed)
            }
            if model.records.isEmpty {
                VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                    Text("No files")
                        .font(DemoType.body)
                        .accessibilityIdentifier("file.browser.empty")
                    Text("Import files, drop them here, or load the built-in samples.")
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(model.records, selection: selection) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.name)
                            .font(DemoType.caption)
                            .lineLimit(1)
                        Text(record.sourceDescription)
                            .font(DemoType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityLabel("\(record.name), \(record.sourceDescription)")
                    .accessibilityIdentifier("file.browser.record.\(record.id)")
                    .id(record.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            Text(model.selectedRecord?.name ?? "Preview")
                .font(DemoType.cardTitle)
                .lineLimit(1)
                .accessibilityIdentifier("file.browser.preview.name")

            HStack(spacing: DemoMetrics.s2) {
                DemoButton("Retry") { _ = model.retryPreview() }
                    .accessibilityIdentifier("file.browser.retry")
                    .disabled(model.selectedID == nil || model.preview == .loading || model.isClosed)
                DemoButton("Cancel") { _ = model.cancelPreview() }
                    .accessibilityIdentifier("file.browser.cancel")
                    .disabled(model.preview != .loading || model.isClosed)
                Spacer(minLength: 0)
            }

            Group {
                switch model.preview {
                case .idle:
                    Text("Select a file to preview its contents.")
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("file.browser.preview.idle")
                case .loading:
                    VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                        ProgressView()
                            .accessibilityLabel("Loading file preview")
                        Text(
                            model.isWaitingForPreviousRead ? "Waiting for the previous read to stop…" : "Reading file…"
                        )
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("file.browser.preview.loading")
                case .ready(let preview):
                    VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                        Text("\(preview.byteCount) UTF-8 bytes")
                            .font(DemoType.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("file.browser.preview.size")
                        ScrollView {
                            Text(preview.text.isEmpty ? "This file is empty." : preview.text)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .accessibilityIdentifier("file.browser.preview.text")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                        Text("Preview unavailable")
                            .font(DemoType.body)
                        Text(message)
                            .font(DemoType.caption)
                            .foregroundStyle(.secondary)
                        Text("Retry reads the same source again. No file has been changed.")
                            .font(DemoType.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("file.browser.preview.failure")
                case .cancelled:
                    VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                        Text(model.isReading ? "Cancelling preview…" : "Preview cancelled")
                            .font(DemoType.body)
                        Text(
                            model.isReading ? "Waiting for the current read to stop." : "Retry to read this file again."
                        )
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("file.browser.preview.cancelled")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
