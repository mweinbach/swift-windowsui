import Foundation
import SwiftWindowsCore
import SwiftWindowsDemo
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum DocumentHostingError: Error, LocalizedError, Equatable {
    case injected
    var errorDescription: String? { "Injected document hosting failure" }
}

private final class HostingReferenceDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.utf8PlainText] }
    init() {}
    init(configuration: FileDocumentReadConfiguration) throws {}
    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}

/// Viewing must not acquire an unrelated fixed-write configuration constraint.
private struct HostingViewingDocument: FileDocument {
    typealias WriteConfiguration = Never
    static var readableContentTypes: [UTType] { [.utf8PlainText] }
    var text: String

    init(configuration: FileDocumentReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: Never) throws -> FileWrapper {
        switch configuration {}
    }
}

@MainActor
private final class DocumentHostingFiles: DocumentFileService {
    let live = LiveDocumentFileService()
    var openOutcome: FileDialogOutcome<URL> = .cancelled
    var saveOutcome: FileDialogOutcome<URL> = .cancelled
    var onOpen: (() -> Void)?
    var onSave: (() -> Void)?
    var beforeRead: (() throws -> Void)?
    var afterRead: (() -> Void)?
    var beforeWrite: (() throws -> Void)?
    private(set) var openChoices = 0
    private(set) var saveChoices = 0
    private(set) var reads = 0
    private(set) var writes = 0
    private(set) var committedWrites = 0
    private(set) var dialogOwners: [FileDialogOwner] = []

    func chooseOpenURL(types: [UTType], owner: FileDialogOwner) -> FileDialogOutcome<URL> {
        openChoices += 1
        dialogOwners.append(owner)
        onOpen?()
        return openOutcome
    }

    func chooseSaveURL(
        name: String?, directory: URL?, type: UTType, owner: FileDialogOwner
    ) -> FileDialogOutcome<URL> {
        saveChoices += 1
        dialogOwners.append(owner)
        onSave?()
        return saveOutcome
    }

    func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
        reads += 1
        try beforeRead?()
        let data = try live.readRegularFile(at: url, maximumBytes: maximumBytes)
        afterRead?()
        return data
    }

    func writeRegularFile(
        to url: URL, provideData: @MainActor (URL) throws -> Data,
        validate: @MainActor () throws -> Void
    ) throws -> Data {
        writes += 1
        try beforeWrite?()
        let bytes = try live.writeRegularFile(to: url, provideData: provideData, validate: validate)
        committedWrites += 1
        return bytes
    }
}

@MainActor
private final class DocumentHostingEvents {
    var created: [WinSwiftUIWindowHost] = []
    var started: [WinSwiftUIWindowHost] = []
    var activated: [WinSwiftUIWindowHost] = []
    var closeRequests = 0
    var terminations = 0
    var factoryCalls = 0
    var scopeCalls = 0
    var beforeFactory: ((WindowGroupConfiguration) throws -> Void)?
    var afterFactory: ((WinSwiftUIWindowHost) throws -> Void)?
    var onStart: ((WinSwiftUIWindowHost) throws -> Void)?
    var onScope: (() -> Void)?
}

/// Every native branch is a safe throwing trap, including when the very
/// admission guard under test regresses. No test can fall into GetMessage.
@MainActor
private final class DocumentHostingRefusingPlatform: PlatformHostFactory {
    let platformName = "Document hosting admission trap"
    private(set) var makeCalls = 0
    private(set) var startCalls = 0
    private(set) var loopCalls = 0

    func makeWindow(configuration: PlatformWindowConfiguration) throws -> any PlatformWindow {
        makeCalls += 1
        throw DocumentHostingError.injected
    }

    func start(window: any PlatformWindow) throws {
        startCalls += 1
        throw DocumentHostingError.injected
    }

    func runEventLoop() throws -> Int32 {
        loopCalls += 1
        throw DocumentHostingError.injected
    }

    func terminateEventLoop() {}
}

@MainActor
private final class DocumentHostingHarness {
    let directory: URL
    let files: DocumentHostingFiles
    let events: DocumentHostingEvents
    let coordinator: WinSwiftUIWindowCoordinator

    init(
        configurations: [WindowGroupConfiguration],
        files: DocumentHostingFiles = DocumentHostingFiles(),
        events: DocumentHostingEvents = DocumentHostingEvents(),
        maximumReadBytes: Int = LiveDocumentFileService.defaultMaximumReadBytes,
        makeUndoManager: @escaping @MainActor () -> WinSwiftUI.UndoManager? = { WinSwiftUI.UndoManager() },
        enablesDocuments: Bool = true
    ) throws {
        self.files = files
        self.events = events
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-windowsui-document-hosting-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let hooks = WindowCoordinatorHooks(
            startWindow: { host in
                events.started.append(host)
                try events.onStart?(host)
                host.windowDidCreate(host.platformWindow)
            },
            requestCloseWindow: { host in
                events.closeRequests += 1
                // A document's commit is separately drained by its fixture.
                if host.windowShouldClose(host.platformWindow) { host.windowWillClose(host.platformWindow) }
            },
            runMessageLoop: { 0 },
            terminateMessageLoop: { events.terminations += 1 },
            activateWindow: { host in
                events.activated.append(host)
                return false
            }
        )
        coordinator = WinSwiftUIWindowCoordinator(
            sceneConfigurations: configurations, hooks: hooks,
            hostFactory: { configuration, _ in
                events.factoryCalls += 1
                try events.beforeFactory?(configuration)
                let host = WinSwiftUIWindowHost(
                    configuration: configuration, renderer: FakeRenderBackend(), batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in
                        SurfaceDescriptor(
                            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1))!,
                            pixelSize: IntSize(width: 640, height: 480), scaleFactor: 1
                        )
                    },
                    startupProbeConfiguration: nil
                )
                events.created.append(host)
                try events.afterFactory?(host)
                return host
            },
            sceneStorageScopeProvider: {
                events.scopeCalls += 1
                events.onScope?()
                return "document-hosting:\(UUID().uuidString)"
            },
            documentServices: enablesDocuments
                ? .headless(files: files, maximumReadBytes: maximumReadBytes, makeUndoManager: makeUndoManager) : nil
        )
    }

    func file(_ name: String = "document.txt", bytes: Data? = nil) throws -> URL {
        let url = directory.appendingPathComponent(name)
        if let bytes { try bytes.write(to: url, options: .atomic) }
        return url
    }

    func cleanup() {
        files.onOpen = nil
        files.onSave = nil
        files.beforeRead = nil
        files.afterRead = nil
        files.beforeWrite = nil
        events.beforeFactory = nil
        events.afterFactory = nil
        events.onStart = nil
        events.onScope = nil
        for record in coordinator.windows { record.host.windowWillClose(record.host.platformWindow) }
        for host in events.created { host.windowWillClose(host.platformWindow) }
        events.created.removeAll()
        events.started.removeAll()
        events.activated.removeAll()
        documentHostingRemoveDirectory(directory)
    }
}

@MainActor
private final class DocumentHostingRecorder {
    struct Sample {
        let configuration: FileDocumentConfiguration<DemoPlainTextDocument>
        let environment: EnvironmentValues
    }
    var samples: [Sample] = []
    var onBuild: ((EnvironmentValues) -> Void)?

    func latest(in context: DocumentWindowContext) throws -> Sample {
        try XCTUnwrap(samples.last { $0.environment.sceneStorageScope == context.environment.sceneStorageScope })
    }
}

@MainActor
private struct DocumentHostingProbe: View {
    typealias Body = Never
    let configuration: FileDocumentConfiguration<DemoPlainTextDocument>
    let recorder: DocumentHostingRecorder
    var body: Never { fatalError("DocumentHostingProbe has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        recorder.samples.append(.init(configuration: configuration, environment: context.environmentValues))
        recorder.onBuild?(context.environmentValues)
        return makeViewComponent(
            DemoDocumentEditor(document: configuration.$document, fileURL: configuration.fileURL), context: context
        )
    }
}

@MainActor
private final class DocumentHostingEnvironmentObject: ObservableObject {}

@MainActor
private final class DocumentHostingReleaseProbe {
    let onRelease: () -> Void
    init(_ onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

@MainActor
private final class DocumentHostingErrorPayload: Error, @unchecked Sendable {
    let onRelease: () -> Void
    init(_ onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

private struct DocumentHostingHistoryPayload: FileDocument {
    static var readableContentTypes: [UTType] { [.utf8PlainText] }
    var text: String
    var payload: DocumentHostingReleaseProbe?

    init(text: String, payload: DocumentHostingReleaseProbe? = nil) {
        self.text = text
        self.payload = payload
    }

    init(configuration: FileDocumentReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
        payload = nil
    }

    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@MainActor
private final class DocumentHostingStateCapture {
    var binding: Binding<Int>?
    weak var owner: DocumentOwnerLease?
    var releaseCount = 0
    var valuesAfterReleaseWrite: [Int] = []
    var ownerValidityDuringRelease: [Bool] = []

    func releaseCallback() {
        releaseCount += 1
        ownerValidityDuringRelease.append(owner?.isValid ?? false)
        binding?.wrappedValue = 99
        valuesAfterReleaseWrite.append(binding?.wrappedValue ?? -1)
    }
}

@MainActor
private struct DocumentHostingMountedState: View {
    @State private var value = 5
    let capture: DocumentHostingStateCapture

    var body: some View {
        capture.binding = $value
        return Text("Mounted value \(value)")
    }
}

@MainActor
private func installDocumentHostingChangePayload(
    _ context: DocumentWindowContext, capture: DocumentHostingStateCapture
) {
    let probe = DocumentHostingReleaseProbe { capture.releaseCallback() }
    context.session.onChange = { withExtendedLifetime(probe) {} }
}

private func documentHostingRemoveDirectory(_ directory: URL) {
    // Delete only this freshly created direct child of the temp directory.
    guard
        directory.deletingLastPathComponent().standardizedFileURL
            == FileManager.default.temporaryDirectory.standardizedFileURL,
        directory.lastPathComponent.hasPrefix("swift-windowsui-document-hosting-")
    else { return XCTFail("Refusing cleanup outside the owned temporary directory") }
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
private func documentHostingConfiguration(
    recorder: DocumentHostingRecorder,
    makeDocument: @escaping @MainActor () -> DemoPlainTextDocument = { DemoPlainTextDocument(text: "A") }
) -> WindowGroupConfiguration {
    DocumentGroup(newDocument: makeDocument()) { configuration in
        DocumentHostingProbe(configuration: configuration, recorder: recorder)
    }.makeWindowConfiguration()
}

@MainActor
private func documentHostingNodes(_ root: ViewNode) -> [ViewNode] {
    [root] + root.children.flatMap(documentHostingNodes)
}

@MainActor
private func documentHostingEditor(_ context: DocumentWindowContext) throws -> ViewNode {
    let runtime = try XCTUnwrap(context.owner.runtime)
    return try XCTUnwrap(
        documentHostingNodes(runtime.root).first {
            $0.accessibilityIdentifier == "document.template.editor"
        })
}

@MainActor
private func documentHostingSave(_ outcome: DocumentSaveOutcome) throws -> DocumentSaveReceipt {
    guard case .saved(let receipt, let isCurrent) = outcome else {
        XCTFail("Expected a real committed save, got \(outcome)")
        throw DocumentHostingError.injected
    }
    XCTAssertTrue(isCurrent)
    return receipt
}

final class DocumentGroupHostingTests: XCTestCase {
    func testDeclarationDoesNotCreateModelsOrBuildContent() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            var factories = 0
            let configuration = documentHostingConfiguration(recorder: recorder) {
                factories += 1
                return DemoPlainTextDocument(text: "same")
            }
            XCTAssertEqual(factories, 0)
            XCTAssertTrue(configuration.content.isEmpty)
            XCTAssertNil(configuration.documentWindowContext)
            XCTAssertTrue(recorder.samples.isEmpty)
            let harness = try DocumentHostingHarness(configurations: [configuration])
            defer { harness.cleanup() }
            _ = try harness.coordinator.bootPrimaryWindow()
            XCTAssertEqual(factories, 1)
            XCTAssertFalse(recorder.samples.isEmpty)
            XCTAssertNil(configuration.documentWindowContext)
        }
    }

    func testTwoNewWindowsHaveIndependentBindingsManagersAndFirstBuildEnvironments() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let harness = try DocumentHostingHarness(configurations: [documentHostingConfiguration(recorder: recorder)])
            defer { harness.cleanup() }
            let firstHost = try harness.coordinator.bootPrimaryWindow()
            let first = try XCTUnwrap(firstHost.documentContext)
            let secondHost = try harness.coordinator.newDocument(from: first)
            let second = try XCTUnwrap(secondHost.documentContext)
            XCTAssertNotEqual(first.session.sessionID, second.session.sessionID)
            XCTAssertNotEqual(first.owner.ownerID, second.owner.ownerID)
            XCTAssertFalse(first.undoManager === second.undoManager)
            XCTAssertNotEqual(first.environment.sceneStorageScope, second.environment.sceneStorageScope)
            for context in [first, second] {
                let initial = try XCTUnwrap(
                    recorder.samples.first {
                        $0.environment.sceneStorageScope == context.environment.sceneStorageScope
                    })
                XCTAssertTrue(initial.environment.undoManager === context.undoManager)
                XCTAssertTrue(initial.environment.supportsMultipleWindows)
                XCTAssertEqual(initial.configuration.document.text, "A")
            }
            let binding = try recorder.latest(in: first).configuration.$document
            binding.text.wrappedValue = "first only"
            XCTAssertEqual(try recorder.latest(in: first).configuration.document.text, "first only")
            XCTAssertEqual(try recorder.latest(in: second).configuration.document.text, "A")
            XCTAssertTrue(first.undoManager?.canUndo == true)
            XCTAssertFalse(second.undoManager?.canUndo == true)
            XCTAssertEqual(harness.coordinator.windowCount, 2)
        }
    }

    func testExplicitNilAndSharedManagersReachTheFirstBuildUnchanged() async throws {
        try await MainActor.run {
            let managers: [WinSwiftUI.UndoManager?] = [nil, WinSwiftUI.UndoManager()]
            for manager in managers {
                let recorder = DocumentHostingRecorder()
                let harness = try DocumentHostingHarness(
                    configurations: [documentHostingConfiguration(recorder: recorder)], makeUndoManager: { manager }
                )
                defer { harness.cleanup() }
                let first = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
                let second = try XCTUnwrap(harness.coordinator.newDocument(from: first).documentContext)
                for context in [first, second] {
                    XCTAssertTrue(context.undoManager === manager)
                    XCTAssertTrue(try recorder.latest(in: context).environment.undoManager === manager)
                    let binding = try recorder.latest(in: context).configuration.$document.text
                    binding.wrappedValue = "changed"
                }
                XCTAssertEqual(manager?.canUndo, manager == nil ? nil : true)
            }
        }
    }

    func testSceneEnvironmentAndEnvironmentObjectMapEveryTypedRebuild() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let model = DocumentHostingEnvironmentObject()
            let scene = DocumentGroup(newDocument: DemoPlainTextDocument()) { configuration in
                DocumentHostingProbe(configuration: configuration, recorder: recorder)
            }
            .environment(\.colorScheme, .dark)
            .environmentObject(model)
            let harness = try DocumentHostingHarness(configurations: [scene.makeWindowConfiguration()])
            defer { harness.cleanup() }
            let first = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            let second = try XCTUnwrap(harness.coordinator.newDocument(from: first).documentContext)
            for context in [first, second] {
                let sample = try recorder.latest(in: context)
                XCTAssertEqual(sample.environment.colorScheme, .dark)
                XCTAssertTrue(
                    sample.environment.environmentObjects.object(DocumentHostingEnvironmentObject.self) === model)
                sample.configuration.$document.text.wrappedValue = "rebuilt"
                let latest = try recorder.latest(in: context)
                XCTAssertEqual(latest.environment.colorScheme, .dark)
                XCTAssertTrue(
                    latest.environment.environmentObjects.object(DocumentHostingEnvironmentObject.self) === model)
                XCTAssertTrue(latest.environment.undoManager === context.undoManager)
            }
        }
    }

    func testInitialEnvironmentActionsAndRetainedNewDocumentButtonAreLive() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let scene = DocumentGroup(newDocument: DemoPlainTextDocument(text: "action source")) { configuration in
                VStack {
                    NewDocumentButton("New document")
                        .accessibilityIdentifier("document.hosting.new")
                    DocumentHostingProbe(configuration: configuration, recorder: recorder)
                }
            }
            let harness = try DocumentHostingHarness(configurations: [scene.makeWindowConfiguration()])
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(host.documentContext)
            let initial = try XCTUnwrap(recorder.samples.first)
            let runtime = try XCTUnwrap(context.owner.runtime)
            let button = try XCTUnwrap(
                documentHostingNodes(runtime.root).first {
                    $0.accessibilityIdentifier == "document.hosting.new"
                })
            runtime.requestFocus(button)
            host.window(
                host.platformWindow,
                keyDown: KeyboardEvent(
                    keyCode: KeyboardKey.enter.rawValue, textInputDelivery: .systemCharacter
                ))
            XCTAssertEqual(harness.coordinator.windowCount, 2, "Normal retained Button routing must reach New.")
            let destination = try harness.file()
            initial.environment.saveDocument(destination)
            XCTAssertEqual(context.session.fileURL, destination)
            XCTAssertEqual(try Data(contentsOf: destination), Data("action source".utf8))
            initial.environment.openDocument(destination)
            XCTAssertEqual(harness.coordinator.windowCount, 2)
            XCTAssertTrue(harness.events.activated.last === host)
            initial.environment.dismissWindow()
            XCTAssertEqual(harness.events.closeRequests, 1)
            XCTAssertEqual(harness.coordinator.windowCount, 2, "The close intent awaits a separate headless commit.")
            XCTAssertNotNil(context.session.closeApproval)
        }
    }

    func testHostedReadLimitCanBeLoweredButCannotExceedTheStageCeiling() async {
        await MainActor.run {
            let files = DocumentHostingFiles()
            let ceiling = LiveDocumentFileService.defaultMaximumReadBytes
            XCTAssertEqual(ceiling, 16 * 1024 * 1024)
            XCTAssertEqual(DocumentWindowServices.headless(files: files).maximumReadBytes, ceiling)
            XCTAssertEqual(
                DocumentWindowServices.headless(files: files, maximumReadBytes: Int.max).maximumReadBytes, ceiling)
            XCTAssertEqual(DocumentWindowServices.headless(files: files, maximumReadBytes: 4).maximumReadBytes, 4)
            XCTAssertEqual(DocumentWindowServices.headless(files: files, maximumReadBytes: 0).maximumReadBytes, 0)
            XCTAssertEqual(DocumentWindowServices.headless(files: files, maximumReadBytes: -1).maximumReadBytes, -1)
        }
    }

    func testNativeGateRejectsBeforeModelFactoryFileReadAndHostFactory() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            var modelFactories = 0
            let configuration = documentHostingConfiguration(recorder: recorder) {
                modelFactories += 1
                return DemoPlainTextDocument()
            }
            let harness = try DocumentHostingHarness(configurations: [configuration], enablesDocuments: false)
            defer { harness.cleanup() }
            let url = try harness.file(bytes: Data("valid".utf8))
            XCTAssertThrowsError(try harness.coordinator.bootPrimaryWindow()) {
                XCTAssertEqual($0 as? WindowCoordinatorError, .nativeDocumentActivationUnavailable)
            }
            XCTAssertThrowsError(try harness.coordinator.openDocument(at: url))
            XCTAssertEqual(modelFactories, 0)
            XCTAssertEqual(harness.files.reads, 0)
            XCTAssertEqual(harness.events.factoryCalls, 0)
            XCTAssertTrue(harness.events.started.isEmpty)
            XCTAssertTrue(recorder.samples.isEmpty)
        }
    }

    func testHeadlessServicesRequireBothExplicitHooksAndHostFactory() async throws {
        try await MainActor.run {
            for (hasHooks, hasFactory) in [(false, false), (true, false), (false, true)] {
                let recorder = DocumentHostingRecorder()
                let files = DocumentHostingFiles()
                let platform = DocumentHostingRefusingPlatform()
                let safeHooks = WindowCoordinatorHooks(
                    startWindow: { _ in throw DocumentHostingError.injected },
                    requestCloseWindow: { _ in }, runMessageLoop: { throw DocumentHostingError.injected },
                    terminateMessageLoop: {}
                )
                let safeFactory: @MainActor (WindowGroupConfiguration, Bool) throws -> WinSwiftUIWindowHost = {
                    configuration, _ in
                    WinSwiftUIWindowHost(
                        configuration: configuration, renderer: FakeRenderBackend(),
                        batchRenderer: nil, startupProbeConfiguration: nil
                    )
                }
                let coordinator = WinSwiftUIWindowCoordinator(
                    sceneConfigurations: [documentHostingConfiguration(recorder: recorder)],
                    platformHostFactory: platform,
                    hooks: hasHooks ? safeHooks : nil, hostFactory: hasFactory ? safeFactory : nil,
                    documentServices: .headless(files: files)
                )
                XCTAssertThrowsError(try coordinator.bootPrimaryWindow()) {
                    XCTAssertEqual($0 as? WindowCoordinatorError, .documentServicesRequireInjectedHost)
                }
                XCTAssertEqual(coordinator.windowCount, 0)
                XCTAssertTrue(recorder.samples.isEmpty)
                XCTAssertEqual(files.reads, 0)
                XCTAssertEqual(platform.makeCalls, 0)
                XCTAssertEqual(platform.startCalls, 0)
                XCTAssertEqual(platform.loopCalls, 0)
            }
        }
    }

    func testDirectUnmaterializedHostAndNativeAdmissionFailClosed() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let host = WinSwiftUIWindowHost(
                configuration: documentHostingConfiguration(recorder: recorder),
                renderer: FakeRenderBackend(), batchRenderer: nil, startupProbeConfiguration: nil
            )
            XCTAssertTrue(host.isClosed)
            XCTAssertNotNil(host.documentActivationError)
            XCTAssertThrowsError(try host.validateNativeActivation()) {
                XCTAssertEqual($0 as? WindowCoordinatorError, .nativeDocumentActivationUnavailable)
            }
            XCTAssertNil(host.platformWindow.nativeHandle)
            XCTAssertTrue(recorder.samples.isEmpty)
        }
    }

    func testKnownReferenceDocumentRejectsWithoutInvokingItsFactory() async throws {
        try await MainActor.run {
            var factories = 0
            func makeDocument() -> HostingReferenceDocument {
                factories += 1
                return HostingReferenceDocument()
            }
            let scene = DocumentGroup(newDocument: makeDocument()) { _ in Text("unsupported") }
            let harness = try DocumentHostingHarness(configurations: [scene.makeWindowConfiguration()])
            defer { harness.cleanup() }
            XCTAssertEqual(factories, 0)
            XCTAssertThrowsError(try harness.coordinator.bootPrimaryWindow()) {
                XCTAssertEqual($0 as? DocumentSessionError, .referenceDocumentUnsupported)
            }
            let url = try harness.file(bytes: Data("bytes".utf8))
            XCTAssertThrowsError(try harness.coordinator.openDocument(at: url))
            XCTAssertEqual(factories, 0)
            XCTAssertEqual(harness.files.reads, 0)
            XCTAssertEqual(harness.events.factoryCalls, 0)
        }
    }

    func testViewingUsesOnlyFixedReadConfigurationAndCannotRegrantWrites() async throws {
        try await MainActor.run {
            var configurations: [FileDocumentConfiguration<HostingViewingDocument>] = []
            let scene = DocumentGroup(viewing: HostingViewingDocument.self) { configuration in
                configurations.append(configuration)
                return Text(configuration.document.text)
            }
            let harness = try DocumentHostingHarness(configurations: [scene.makeWindowConfiguration()])
            defer { harness.cleanup() }
            XCTAssertTrue(configurations.isEmpty)
            XCTAssertThrowsError(try harness.coordinator.bootPrimaryWindow()) {
                XCTAssertEqual($0 as? WindowCoordinatorError, .documentInputRequired)
            }
            let url = try harness.file(bytes: Data("read only".utf8))
            let context = try XCTUnwrap(harness.coordinator.openDocument(at: url).documentContext)
            var configuration = try XCTUnwrap(configurations.last)
            XCTAssertFalse(configuration.isEditable)
            XCTAssertEqual(configuration.document.text, "read only")
            configuration.isEditable = true
            configuration.$document.text.wrappedValue = "not allowed"
            XCTAssertEqual(configuration.document.text, "read only")
            XCTAssertFalse(context.session.isDirty)
            guard case .failed(let error) = context.save() else { return XCTFail("Viewing save must fail") }
            XCTAssertEqual(error as? DocumentSessionError, .readOnly)
            XCTAssertEqual(harness.files.writes, 0)
        }
    }

    func testSharedDemoOpensEditsSavesAndReopensActualUTF8BytesThroughTheHost() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let url = try harness.file(bytes: Data("original".utf8))
            let host = try harness.coordinator.openDocument(at: url)
            let context = try XCTUnwrap(host.documentContext)
            let runtime = try XCTUnwrap(context.owner.runtime)
            let editor = try documentHostingEditor(context)
            _ = runtime.renderScene(at: 0)
            runtime.requestFocus(editor)
            host.window(
                host.platformWindow,
                keyDown: KeyboardEvent(
                    keyCode: 65, modifiers: .control, textInputDelivery: .systemCharacter
                ))
            let replacement = "B👩🏽‍💻\nC"
            host.window(host.platformWindow, didInputText: replacement)
            XCTAssertTrue(context.session.isDirty)
            let receipt = try documentHostingSave(context.save())
            XCTAssertEqual(receipt.bytes, Data(replacement.utf8))
            XCTAssertEqual(try Data(contentsOf: url), receipt.bytes)
            XCTAssertEqual(harness.files.committedWrites, 1)
            XCTAssertFalse(context.session.isDirty)
            XCTAssertTrue(try documentHostingEditor(context) === editor)
            XCTAssertTrue(context.undoManager?.canUndo == true, "Saving preserves the document history.")
            host.window(
                host.platformWindow,
                keyDown: KeyboardEvent(
                    keyCode: 90, modifiers: .control, textInputDelivery: .systemCharacter
                ))
            XCTAssertTrue(context.session.isDirty)
            XCTAssertEqual(try Data(contentsOf: url), receipt.bytes, "Undo does not silently write to disk.")
            host.window(
                host.platformWindow,
                keyDown: KeyboardEvent(
                    keyCode: 90, modifiers: [.control, .shift], textInputDelivery: .systemCharacter
                ))
            XCTAssertFalse(context.session.isDirty)
            let survivor = try XCTUnwrap(harness.coordinator.newDocument(from: context).documentContext)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            let approval = try XCTUnwrap(context.session.closeApproval)
            XCTAssertTrue(host.commitHeadlessDocumentClose(approval))
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            let reopened = try harness.coordinator.openDocument(at: url, from: survivor)
            let reopenedContext = try XCTUnwrap(reopened.documentContext)
            XCTAssertNotEqual(reopenedContext.session.sessionID, context.session.sessionID)
            XCTAssertEqual(reopenedContext.session.savedBytes, receipt.bytes)
            XCTAssertFalse(reopenedContext.session.isDirty)
            XCTAssertEqual(harness.files.reads, 2)
        }
    }

    func testOpeningTheSameStandardizedURLActivatesWithoutReadingAgain() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let bytes = Data("\u{FEFF}e\u{301}\r\nline\r".utf8)
            let url = try harness.file("mixed.TXT", bytes: bytes)
            let first = try harness.coordinator.openDocument(at: url)
            let firstContext = try XCTUnwrap(first.documentContext)
            let alternate = harness.directory.appendingPathComponent("unused/../mixed.TXT")
            let repeated = try harness.coordinator.openDocument(at: alternate, from: firstContext)
            XCTAssertTrue(repeated === first)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertEqual(harness.files.reads, 1)
            XCTAssertEqual(firstContext.session.savedBytes, bytes)
            XCTAssertTrue(harness.events.activated.last === first)
            XCTAssertEqual(harness.events.factoryCalls, 1)
        }
    }

    func testSaveCancelFailureAndRetryKeepTheEditorAndShowCurrentError() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let harness = try DocumentHostingHarness(configurations: [documentHostingConfiguration(recorder: recorder)])
            defer { harness.cleanup() }
            let originalBytes = Data("saved A".utf8)
            let url = try harness.file(bytes: originalBytes)
            let context = try XCTUnwrap(harness.coordinator.openDocument(at: url).documentContext)
            let editor = try documentHostingEditor(context)
            let runtime = try XCTUnwrap(context.owner.runtime)
            let savedCheckpoint = context.session.savedCheckpoint
            let binding = try recorder.latest(in: context).configuration.$document.text
            binding.wrappedValue = "unsaved B"
            guard case .cancelled = context.saveAs() else { return XCTFail("Expected cancelled selection") }
            XCTAssertEqual(harness.files.writes, 0)
            XCTAssertEqual(context.session.fileURL, url.standardizedFileURL)
            XCTAssertEqual(context.session.savedCheckpoint, savedCheckpoint)
            XCTAssertTrue(context.session.isDirty)
            harness.files.saveOutcome = .failed(DocumentHostingError.injected)
            guard case .failed = context.saveAs() else { return XCTFail("Expected the typed chooser failure") }
            XCTAssertTrue(try documentHostingEditor(context) === editor)
            XCTAssertTrue(
                documentHostingNodes(runtime.root).contains {
                    $0.text == DocumentHostingError.injected.localizedDescription
                })
            XCTAssertEqual(try Data(contentsOf: url), originalBytes)
            let destination = try harness.file("saved-as.txt")
            harness.files.saveOutcome = .selected(destination)
            let receipt = try documentHostingSave(context.saveAs())
            XCTAssertEqual(receipt.bytes, Data("unsaved B".utf8))
            XCTAssertEqual(try Data(contentsOf: destination), receipt.bytes)
            XCTAssertEqual(context.session.fileURL, destination)
            XCTAssertEqual(try recorder.latest(in: context).configuration.fileURL, destination)
            XCTAssertNil(context.lastError)
            XCTAssertFalse(context.session.isDirty)
            XCTAssertTrue(context.undoManager?.canUndo == true)
            XCTAssertTrue(try documentHostingEditor(context) === editor)
        }
    }

    func testOpenFailurePreservesTheCurrentDocumentAndRetryUsesTheSameOwner() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let harness = try DocumentHostingHarness(configurations: [documentHostingConfiguration(recorder: recorder)])
            defer { harness.cleanup() }
            let source = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            let editor = try documentHostingEditor(source)
            let url = try harness.file()
            XCTAssertThrowsError(try harness.coordinator.openDocument(at: url, from: source))
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertEqual(try recorder.latest(in: source).configuration.document.text, "A")
            XCTAssertNotNil(source.lastError)
            XCTAssertTrue(try documentHostingEditor(source) === editor)
            try Data("valid retry".utf8).write(to: url, options: .atomic)
            let opened = try harness.coordinator.openDocument(at: url, from: source)
            XCTAssertEqual(opened.documentContext?.session.savedBytes, Data("valid retry".utf8))
            XCTAssertNil(source.lastError)
            XCTAssertTrue(source.owner.isValid)
            XCTAssertEqual(harness.coordinator.windowCount, 2)
            XCTAssertTrue(try documentHostingEditor(source) === editor)
        }
    }

    func testUnsupportedExtensionInvalidUTF8DirectoryAndReadLimitNeverAdmitAWindow() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(
                configurations: DemoDocumentScene().makeWindowConfigurations(), maximumReadBytes: 4
            )
            defer { harness.cleanup() }
            let source = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            let unsupported = try harness.file("source.unknown", bytes: Data("A".utf8))
            XCTAssertThrowsError(try harness.coordinator.openDocument(at: unsupported, from: source)) {
                XCTAssertEqual($0 as? WindowCoordinatorError, .unsupportedDocumentExtension("unknown"))
            }
            XCTAssertEqual(harness.files.reads, 0)
            let invalid = try harness.file("invalid.txt", bytes: Data([0xC3, 0x28]))
            XCTAssertThrowsError(try harness.coordinator.openDocument(at: invalid, from: source)) {
                XCTAssertEqual($0 as? DemoPlainTextDocument.ReadError, .invalidUTF8)
            }
            let directory = try harness.file("package.txt")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            XCTAssertThrowsError(try harness.coordinator.openDocument(at: directory, from: source)) {
                XCTAssertEqual($0 as? DocumentFileServiceError, .notRegularFile)
            }
            let oversized = try harness.file("large.txt", bytes: Data("12345".utf8))
            XCTAssertThrowsError(try harness.coordinator.openDocument(at: oversized, from: source)) {
                XCTAssertEqual($0 as? DocumentFileServiceError, .readLimitExceeded(maximumBytes: 4))
            }
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertEqual(harness.events.factoryCalls, 1)
            XCTAssertTrue(source.owner.isValid)
            let exact = try harness.file("exact.txt", bytes: Data("1234".utf8))
            XCTAssertNoThrow(try harness.coordinator.openDocument(at: exact, from: source))
            XCTAssertEqual(harness.coordinator.windowCount, 2)
        }
    }

    func testOpenChooserCancellationAndFailureStayDistinctWithExplicitOwner() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let source = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            XCTAssertNil(try harness.coordinator.chooseOpenDocument(from: source))
            XCTAssertNil(source.lastError)
            harness.files.openOutcome = .failed(FileDialogError.nativeFailure(72))
            XCTAssertThrowsError(try harness.coordinator.chooseOpenDocument(from: source)) {
                XCTAssertEqual($0 as? FileDialogError, .nativeFailure(72))
            }
            XCTAssertEqual(source.lastError as? FileDialogError, .nativeFailure(72))
            XCTAssertEqual(harness.files.reads, 0)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertEqual(harness.files.dialogOwners.count, 2)
            for owner in harness.files.dialogOwners {
                guard case .hosted(nil) = owner else {
                    return XCTFail("Headless requests must never use active-window fallback")
                }
            }
        }
    }

    func testInvalidURLFormsRejectBeforeStandardizationDeduplicationOrRead() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let source = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            let literal = try harness.file("bad%00name.txt", bytes: Data("literal filename".utf8))
            let embeddedNUL = try XCTUnwrap(URL(string: "bad%00name.txt", relativeTo: harness.directory)?.absoluteURL)
            let remote = try XCTUnwrap(URL(string: "https://example.invalid/document.txt"))
            let authority = try XCTUnwrap(URL(string: "file://unowned.invalid/C:/document.txt"))
            for invalid in [embeddedNUL, remote, authority] {
                XCTAssertThrowsError(try harness.coordinator.openDocument(at: invalid, from: source)) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .invalidFileURL)
                }
            }
            XCTAssertEqual(harness.files.reads, 0)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertTrue(harness.events.activated.isEmpty)
            XCTAssertNoThrow(try harness.coordinator.openDocument(at: literal, from: source))
            XCTAssertEqual(harness.files.reads, 1)
        }
    }

    func testChooserReentryMutationOrCloseRejectsSelectionBeforeReading() async throws {
        try await MainActor.run {
            for closesOwner in [false, true] {
                let recorder = DocumentHostingRecorder()
                let harness = try DocumentHostingHarness(configurations: [
                    documentHostingConfiguration(recorder: recorder)
                ])
                defer { harness.cleanup() }
                let host = try harness.coordinator.bootPrimaryWindow()
                let source = try XCTUnwrap(host.documentContext)
                let binding = try recorder.latest(in: source).configuration.$document.text
                let url = try harness.file(bytes: Data("destination".utf8))
                harness.files.openOutcome = .selected(url)
                harness.files.onOpen = {
                    if closesOwner {
                        host.windowWillClose(host.platformWindow)
                    } else {
                        binding.wrappedValue = "newer source"
                    }
                }
                XCTAssertThrowsError(try harness.coordinator.chooseOpenDocument(from: source))
                XCTAssertEqual(harness.files.reads, 0)
                XCTAssertEqual(harness.events.factoryCalls, 1)
                XCTAssertEqual(harness.coordinator.windowCount, closesOwner ? 0 : 1)
                XCTAssertNil(
                    source.lastError, "A superseded route cannot publish an error into a newer or retired owner.")
            }
        }
    }

    func testRevisionChangeAfterReadStopsBeforeDecoderAndHostConstruction() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let harness = try DocumentHostingHarness(configurations: [documentHostingConfiguration(recorder: recorder)])
            defer { harness.cleanup() }
            let source = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            let binding = try recorder.latest(in: source).configuration.$document.text
            let invalidUTF8 = try harness.file(bytes: Data([0xFF]))
            harness.files.afterRead = { binding.wrappedValue = "changed during read" }
            XCTAssertThrowsError(try harness.coordinator.openDocument(at: invalidUTF8, from: source)) {
                XCTAssertEqual($0 as? DocumentSessionError, .supersededOperation)
            }
            XCTAssertEqual(harness.files.reads, 1)
            XCTAssertEqual(harness.events.factoryCalls, 1)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertNil(source.lastError)
            XCTAssertEqual(binding.wrappedValue, "changed during read")
        }
    }

    func testNewFactoryRevisionChangeAbandonsThePreparedSessionBeforeHosting() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            var onFactory: (() -> Void)?
            let configuration = documentHostingConfiguration(recorder: recorder) {
                onFactory?()
                return DemoPlainTextDocument(text: "new")
            }
            let harness = try DocumentHostingHarness(configurations: [configuration])
            defer {
                onFactory = nil
                harness.cleanup()
            }
            let source = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            let binding = try recorder.latest(in: source).configuration.$document.text
            onFactory = { binding.wrappedValue = "newer caller" }
            XCTAssertThrowsError(try harness.coordinator.newDocument(from: source))
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertEqual(harness.events.factoryCalls, 1)
            XCTAssertEqual(binding.wrappedValue, "newer caller")
            XCTAssertNil(source.lastError)
        }
    }

    func testManagerAndScopeCallbacksCannotAdmitAChildAfterItsCallerCloses() async throws {
        try await MainActor.run {
            for closesInManager in [false, true] {
                let recorder = DocumentHostingRecorder()
                var onManager: (() -> Void)?
                let harness = try DocumentHostingHarness(
                    configurations: [documentHostingConfiguration(recorder: recorder)],
                    makeUndoManager: {
                        onManager?()
                        return WinSwiftUI.UndoManager()
                    }
                )
                defer {
                    onManager = nil
                    harness.cleanup()
                }
                let host = try harness.coordinator.bootPrimaryWindow()
                let source = try XCTUnwrap(host.documentContext)
                let close = { host.windowWillClose(host.platformWindow) }
                if closesInManager { onManager = close } else { harness.events.onScope = close }
                XCTAssertThrowsError(try harness.coordinator.newDocument(from: source))
                XCTAssertEqual(harness.coordinator.windowCount, 0)
                XCTAssertEqual(harness.events.factoryCalls, 1)
                XCTAssertEqual(harness.events.terminations, 1)
                XCTAssertFalse(source.owner.isValid)
            }
        }
    }

    func testFactoryFailureAfterConstructingAHostRevokesItAndAllowsRetry() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            harness.events.afterFactory = { _ in throw DocumentHostingError.injected }
            XCTAssertThrowsError(try harness.coordinator.bootPrimaryWindow())
            let abandoned = try XCTUnwrap(harness.events.created.first)
            let context = try XCTUnwrap(abandoned.documentContext)
            XCTAssertTrue(abandoned.isClosed)
            XCTAssertFalse(context.owner.isValid)
            XCTAssertEqual(context.session.closePhase, .closed)
            XCTAssertEqual(harness.coordinator.windowCount, 0)
            XCTAssertTrue(harness.events.started.isEmpty)
            XCTAssertEqual(harness.events.terminations, 0)
            harness.events.afterFactory = nil
            XCTAssertNoThrow(try harness.coordinator.bootPrimaryWindow())
            XCTAssertEqual(harness.coordinator.windowCount, 1)
        }
    }

    func testStartFailureRevokesOnlyTheChildAndLeavesTheCallerAvailable() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let source = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            harness.events.onStart = { _ in throw DocumentHostingError.injected }
            XCTAssertThrowsError(try harness.coordinator.newDocument(from: source))
            let child = try XCTUnwrap(harness.events.created.last)
            XCTAssertTrue(child.isClosed)
            XCTAssertFalse(child.documentContext?.owner.isValid == true)
            XCTAssertTrue(source.owner.isValid)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertEqual(harness.events.terminations, 0)
            XCTAssertEqual(source.lastError as? DocumentHostingError, .injected)
            harness.events.onStart = nil
            XCTAssertNoThrow(try harness.coordinator.newDocument(from: source))
            XCTAssertEqual(harness.coordinator.windowCount, 2)
        }
    }

    func testClosingTheLastCallerDuringChildStartupStillTerminatesAfterRollback() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let source = try XCTUnwrap(host.documentContext)
            harness.events.onStart = { _ in host.windowWillClose(host.platformWindow) }
            XCTAssertThrowsError(try harness.coordinator.newDocument(from: source))
            XCTAssertEqual(harness.coordinator.windowCount, 0)
            XCTAssertEqual(harness.events.terminations, 1)
            XCTAssertTrue(harness.events.created.allSatisfy(\.isClosed))
            XCTAssertTrue(harness.events.created.allSatisfy { $0.documentContext?.owner.isValid == false })
        }
    }

    func testHostClosedDuringStartIsNotReportedAsSuccessful() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            _ = try harness.coordinator.bootPrimaryWindow()
            harness.events.onStart = { host in host.windowWillClose(host.platformWindow) }
            XCTAssertThrowsError(try harness.coordinator.newDocument()) {
                XCTAssertEqual($0 as? WindowCoordinatorError, .windowClosedDuringStartup)
            }
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertEqual(harness.events.terminations, 0)
            XCTAssertTrue(harness.events.created.last?.isClosed == true)
        }
    }

    func testDismissDuringFirstBuildCancelsAdmissionBeforeStart() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            recorder.onBuild = { environment in
                recorder.onBuild = nil
                environment.dismissWindow()
            }
            let harness = try DocumentHostingHarness(configurations: [documentHostingConfiguration(recorder: recorder)])
            defer {
                recorder.onBuild = nil
                harness.cleanup()
            }
            XCTAssertThrowsError(try harness.coordinator.bootPrimaryWindow())
            XCTAssertEqual(harness.coordinator.windowCount, 0)
            XCTAssertTrue(harness.events.started.isEmpty)
            XCTAssertTrue(harness.events.created.first?.isClosed == true)
            XCTAssertEqual(harness.events.terminations, 0)
        }
    }

    func testRejectedHostCannotRevokeAnAlreadyClaimedContext() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let original = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(original.documentContext)
            let copiedConfiguration = try XCTUnwrap(harness.coordinator.windows.first?.configuration)
            let rejected = WinSwiftUIWindowHost(
                configuration: copiedConfiguration, renderer: FakeRenderBackend(),
                batchRenderer: nil, startupProbeConfiguration: nil
            )
            XCTAssertTrue(rejected.isClosed)
            XCTAssertNotNil(rejected.documentActivationError)
            XCTAssertNil(rejected.documentContext)
            XCTAssertTrue(context.owner.isValid)
            XCTAssertTrue(context.host === original)
            XCTAssertFalse(original.isClosed)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertFalse(context.session.closePhase == .closed)
        }
    }

    func testBorrowedHostFromAnotherCoordinatorIsRejectedWithoutTeardown() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let original = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(original.documentContext)
            var starts = 0
            let other = WinSwiftUIWindowCoordinator(
                sceneConfigurations: DemoDocumentScene().makeWindowConfigurations(),
                hooks: WindowCoordinatorHooks(
                    startWindow: { _ in starts += 1 }, requestCloseWindow: { _ in },
                    runMessageLoop: { 0 }, terminateMessageLoop: {}
                ),
                hostFactory: { _, _ in original },
                documentServices: .headless(files: DocumentHostingFiles())
            )
            XCTAssertThrowsError(try other.bootPrimaryWindow()) {
                XCTAssertEqual($0 as? WindowCoordinatorError, .documentContextMismatch)
            }
            XCTAssertEqual(starts, 0)
            XCTAssertEqual(other.windowCount, 0)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertTrue(context.owner.isValid)
            XCTAssertFalse(original.isClosed)
        }
    }

    func testEscapedActionsAndBindingsDoNothingAfterTheirOwnerCloses() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let harness = try DocumentHostingHarness(configurations: [documentHostingConfiguration(recorder: recorder)])
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(host.documentContext)
            let sample = try recorder.latest(in: context)
            let destination = try harness.file()
            host.windowWillClose(host.platformWindow)
            sample.configuration.$document.text.wrappedValue = "late write"
            sample.environment.newDocument()
            sample.environment.openDocument(destination)
            sample.environment.saveDocument(destination)
            sample.environment.dismissWindow()
            XCTAssertEqual(sample.configuration.document.text, "A")
            XCTAssertEqual(harness.events.factoryCalls, 1)
            XCTAssertEqual(harness.files.reads, 0)
            XCTAssertEqual(harness.files.writes, 0)
            XCTAssertEqual(harness.events.closeRequests, 0)
            XCTAssertEqual(harness.coordinator.windowCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testSaveDialogCannotStartAnotherDocumentOperationOnItsOwner() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let context = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            let destination = try harness.file()
            harness.files.saveOutcome = .selected(destination)
            var nestedError: Error?
            harness.files.onSave = {
                do { _ = try harness.coordinator.newDocument(from: context) } catch { nestedError = error }
                guard case .busy = context.saveAs() else { return XCTFail("Nested save must be busy") }
            }
            _ = try documentHostingSave(context.save())
            XCTAssertEqual(nestedError as? WindowCoordinatorError, .documentOperationBusy)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertEqual(harness.files.saveChoices, 1)
            XCTAssertEqual(harness.files.committedWrites, 1)
            XCTAssertFalse(context.isRoutingDocument)
        }
    }

    func testDirtyCloseCoalescesCancelAndDiscardWithoutWritingOrEarlyRemoval() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(host.documentContext)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            let firstIntent = try XCTUnwrap(context.session.pendingCloseIntent)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            XCTAssertEqual(context.session.pendingCloseIntent, firstIntent)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            guard case .cancelled = context.session.resolveCloseIntent(id: firstIntent.id, choice: .cancel) else {
                return XCTFail("Expected cancel")
            }
            XCTAssertTrue(context.owner.isValid)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            let secondIntent = try XCTUnwrap(context.session.pendingCloseIntent)
            XCTAssertNotEqual(secondIntent.id, firstIntent.id)
            guard
                case .approved(let approval) = context.session.resolveCloseIntent(id: secondIntent.id, choice: .discard)
            else {
                return XCTFail("Expected discard approval")
            }
            XCTAssertEqual(harness.files.writes, 0)
            XCTAssertFalse(
                host.windowShouldClose(host.platformWindow), "A headless approval is never a native close vote.")
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertTrue(host.commitHeadlessDocumentClose(approval))
            XCTAssertFalse(host.commitHeadlessDocumentClose(approval))
            XCTAssertEqual(context.session.closePhase, .closed)
            XCTAssertFalse(context.owner.isValid)
            XCTAssertEqual(harness.coordinator.windowCount, 0)
            XCTAssertEqual(harness.events.terminations, 1)
        }
    }

    func testSaveCloseCancellationFailureAndSuccessfulReceiptCommitDiffer() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(host.documentContext)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            let cancelledIntent = try XCTUnwrap(context.session.pendingCloseIntent)
            guard case .cancelled = context.session.resolveCloseIntent(id: cancelledIntent.id, choice: .save) else {
                return XCTFail("Cancelled Save panel cannot approve close")
            }
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            let failedIntent = try XCTUnwrap(context.session.pendingCloseIntent)
            harness.files.saveOutcome = .failed(DocumentHostingError.injected)
            guard case .failed = context.session.resolveCloseIntent(id: failedIntent.id, choice: .save) else {
                return XCTFail("Failed save cannot approve close")
            }
            XCTAssertTrue(context.owner.isValid)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            let destination = try harness.file()
            harness.files.saveOutcome = .selected(destination)
            guard case .approved(let approval) = context.session.resolveCloseIntent(id: failedIntent.id, choice: .save)
            else {
                return XCTFail("A matching actual save should approve this intent")
            }
            XCTAssertNotNil(approval.saveReceiptID)
            XCTAssertEqual(try Data(contentsOf: destination), Data())
            XCTAssertEqual(harness.files.committedWrites, 1)
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertTrue(host.commitHeadlessDocumentClose(approval))
            XCTAssertEqual(harness.coordinator.windowCount, 0)
        }
    }

    func testCloseApprovalCannotReviveAfterPolicyDisablesAndEnablesAgain() async throws {
        try await MainActor.run {
            let harness = try DocumentHostingHarness(configurations: DemoDocumentScene().makeWindowConfigurations())
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(host.documentContext)
            let runtime = try XCTUnwrap(context.owner.runtime)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            let intent = try XCTUnwrap(context.session.pendingCloseIntent)
            guard case .approved(let approval) = context.session.resolveCloseIntent(id: intent.id, choice: .discard)
            else {
                return XCTFail("Expected approval")
            }
            runtime.root.windowDismissBehavior = .disabled
            XCTAssertFalse(host.commitHeadlessDocumentClose(approval))
            XCTAssertNil(context.session.closeApproval)
            runtime.root.windowDismissBehavior = .enabled
            XCTAssertFalse(host.commitHeadlessDocumentClose(approval))
            XCTAssertEqual(harness.coordinator.windowCount, 1)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            let replacement = try XCTUnwrap(context.session.pendingCloseIntent)
            XCTAssertNotEqual(replacement.id, intent.id)
        }
    }

    func testCloseReservationBlocksCommandsAndWritesUntilReleased() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let harness = try DocumentHostingHarness(configurations: [documentHostingConfiguration(recorder: recorder)])
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(host.documentContext)
            let sample = try recorder.latest(in: context)
            let destination = try harness.file()
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            let intent = try XCTUnwrap(context.session.pendingCloseIntent)
            guard case .approved(let approval) = context.session.resolveCloseIntent(id: intent.id, choice: .discard)
            else {
                return XCTFail("Expected approval")
            }
            XCTAssertTrue(context.session.reserveClose(approval: approval, isHostSettled: true))
            sample.environment.newDocument()
            sample.environment.openDocument(destination)
            sample.environment.saveDocument(destination)
            sample.environment.dismissWindow()
            sample.configuration.$document.text.wrappedValue = "late destruction callback"
            XCTAssertThrowsError(try harness.coordinator.newDocument(from: context))
            guard case .busy = context.saveAs() else { return XCTFail("Reserved owner must reject Save") }
            XCTAssertEqual(sample.configuration.document.text, "A")
            XCTAssertEqual(harness.events.factoryCalls, 1)
            XCTAssertEqual(harness.events.closeRequests, 0)
            XCTAssertEqual(harness.files.reads, 0)
            XCTAssertEqual(harness.files.writes, 0)
            XCTAssertEqual(harness.files.saveChoices, 0)
            context.session.releaseCloseReservation(approval)
            XCTAssertFalse(context.owner.hasCloseCommitReservation)
            XCTAssertNoThrow(try harness.coordinator.newDocument(from: context))
        }
    }

    func testClearingAnErrorCannotReenterSaveOrSaveANewerRevision() async throws {
        try await MainActor.run {
            let recorder = DocumentHostingRecorder()
            let harness = try DocumentHostingHarness(configurations: [documentHostingConfiguration(recorder: recorder)])
            defer { harness.cleanup() }
            let context = try XCTUnwrap(harness.coordinator.bootPrimaryWindow().documentContext)
            let binding = try recorder.latest(in: context).configuration.$document.text
            let destination = try harness.file()
            var nestedWasBusy = false
            var releases = 0
            context.reportRoutingError(
                DocumentHostingErrorPayload {
                    releases += 1
                    if case .busy = context.save(to: destination) { nestedWasBusy = true }
                    binding.wrappedValue = "changed by error cleanup"
                })
            guard case .superseded = context.save(to: destination) else {
                return XCTFail("Preflight cleanup changed the captured revision")
            }
            XCTAssertEqual(releases, 1)
            XCTAssertTrue(nestedWasBusy)
            XCTAssertEqual(harness.files.writes, 0)
            XCTAssertEqual(binding.wrappedValue, "changed by error cleanup")
            XCTAssertFalse(context.isRoutingDocument)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            let receipt = try documentHostingSave(context.save(to: destination))
            XCTAssertEqual(receipt.bytes, Data("changed by error cleanup".utf8))
        }
    }

    func testTeardownRevokesMountedStateBeforeReleasingSessionChangePayload() async throws {
        try await MainActor.run {
            let capture = DocumentHostingStateCapture()
            let scene = DocumentGroup(newDocument: DemoPlainTextDocument()) { _ in
                DocumentHostingMountedState(capture: capture)
            }
            let harness = try DocumentHostingHarness(configurations: [scene.makeWindowConfiguration()])
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(host.documentContext)
            capture.owner = context.owner
            XCTAssertEqual(capture.binding?.wrappedValue, 5)
            installDocumentHostingChangePayload(context, capture: capture)
            XCTAssertEqual(capture.releaseCount, 0)
            host.windowWillClose(host.platformWindow)
            XCTAssertEqual(capture.releaseCount, 1)
            XCTAssertEqual(capture.ownerValidityDuringRelease, [false])
            XCTAssertEqual(capture.valuesAfterReleaseWrite, [5])
            XCTAssertEqual(capture.binding?.wrappedValue, 5)
        }
    }

    func testTeardownRevokesMountedStateBeforePurgingDocumentHistoryPayload() async throws {
        try await MainActor.run {
            let capture = DocumentHostingStateCapture()
            var configuration: FileDocumentConfiguration<DocumentHostingHistoryPayload>?
            let scene = DocumentGroup(
                newDocument: DocumentHostingHistoryPayload(
                    text: "A", payload: DocumentHostingReleaseProbe { capture.releaseCallback() }
                )
            ) { value in
                configuration = value
                return VStack {
                    DocumentHostingMountedState(capture: capture)
                    Text(value.document.text)
                }
            }
            let harness = try DocumentHostingHarness(configurations: [scene.makeWindowConfiguration()])
            defer { harness.cleanup() }
            let host = try harness.coordinator.bootPrimaryWindow()
            let context = try XCTUnwrap(host.documentContext)
            capture.owner = context.owner
            let binding = try XCTUnwrap(configuration).$document
            binding.wrappedValue = DocumentHostingHistoryPayload(text: "B")
            XCTAssertTrue(context.undoManager?.canUndo == true)
            XCTAssertEqual(capture.releaseCount, 0, "The inverse owns the old payload until teardown.")
            host.windowWillClose(host.platformWindow)
            XCTAssertEqual(capture.releaseCount, 1)
            XCTAssertEqual(capture.ownerValidityDuringRelease, [false])
            XCTAssertEqual(capture.valuesAfterReleaseWrite, [5])
            XCTAssertEqual(binding.wrappedValue.text, "B")
            XCTAssertFalse(context.undoManager?.canUndo == true)
        }
    }

    func testHostDeinitRevokesMountedStateBeforeReleasingSessionPayload() async throws {
        try await MainActor.run {
            let capture = DocumentHostingStateCapture()
            let scene = DocumentGroup(newDocument: DemoPlainTextDocument()) { _ in
                DocumentHostingMountedState(capture: capture)
            }
            var harness: DocumentHostingHarness? = try DocumentHostingHarness(configurations: [
                scene.makeWindowConfiguration()
            ])
            let directory = try XCTUnwrap(harness).directory
            defer {
                harness?.cleanup()
                if harness == nil { documentHostingRemoveDirectory(directory) }
            }
            var host: WinSwiftUIWindowHost? = try harness?.coordinator.bootPrimaryWindow()
            weak var observedHost = host
            let context = try XCTUnwrap(host?.documentContext)
            capture.owner = context.owner
            installDocumentHostingChangePayload(context, capture: capture)
            host = nil
            harness?.events.created.removeAll()
            harness?.events.started.removeAll()
            harness = nil
            XCTAssertNil(observedHost, "Escaped document and State bindings must not retain their host.")
            XCTAssertEqual(capture.releaseCount, 1)
            XCTAssertEqual(capture.ownerValidityDuringRelease, [false])
            XCTAssertEqual(capture.valuesAfterReleaseWrite, [5])
            XCTAssertFalse(context.owner.isValid)
            XCTAssertEqual(context.session.closePhase, .closed)
        }
    }

    func testStandardWrapperRegularFileFlagIncludesEmptyButRejectsHybridAndDirectory() async {
        await MainActor.run {
            XCTAssertFalse(FileWrapper().isRegularFile)
            XCTAssertTrue(FileWrapper(regularFileWithContents: Data()).isRegularFile)
            XCTAssertFalse(FileWrapper(directoryWithFileWrappers: [:]).isRegularFile)
            let hybrid = FileWrapper(regularFileWithContents: Data("bytes".utf8))
            hybrid.fileWrappers = [:]
            XCTAssertFalse(hybrid.isRegularFile)
        }
    }
}

// Policy-union regressions are appended so the original document-hosting cases
// retain their exact source and assertions.
@MainActor
private final class DocumentPolicySessionSpy: AnyDocumentSession {
    let base: any AnyDocumentSession
    private(set) var contentCalls = 0
    private(set) var closeRequests = 0
    private(set) var invalidations = 0

    init(_ base: any AnyDocumentSession) { self.base = base }

    var sessionID: Foundation.UUID { base.sessionID }
    var fileURL: URL? { base.fileURL }
    var isEditable: Bool { base.isEditable }
    var isDirty: Bool { base.isDirty }
    var mutationRevision: UInt64 { base.mutationRevision }
    var currentCheckpoint: DocumentCheckpoint { base.currentCheckpoint }
    var savedCheckpoint: DocumentCheckpoint? { base.savedCheckpoint }
    var savedBytes: Data? { base.savedBytes }
    var lastError: Error? { base.lastError }
    var hasActiveOperation: Bool { base.hasActiveOperation }
    var pendingCloseIntent: DocumentCloseIntent? { base.pendingCloseIntent }
    var closeApproval: DocumentCloseApproval? { base.closeApproval }
    var closePhase: DocumentClosePhase { base.closePhase }
    var onChange: (@MainActor () -> Void)? {
        get { base.onChange }
        set { base.onChange = newValue }
    }

    func makeContent() -> [AnyView] {
        contentCalls += 1
        return base.makeContent()
    }

    func save() -> DocumentSaveOutcome { base.save() }
    func saveAs() -> DocumentSaveOutcome { base.saveAs() }
    func save(to url: URL) -> DocumentSaveOutcome { base.save(to: url) }
    func requestClose(isHostSettled: Bool) -> DocumentCloseRequest {
        closeRequests += 1
        return base.requestClose(isHostSettled: isHostSettled)
    }

    func resolveCloseIntent(id: Foundation.UUID, choice: DocumentCloseChoice) -> DocumentCloseResolution {
        base.resolveCloseIntent(id: id, choice: choice)
    }

    func invalidateCloseForHostChange() { base.invalidateCloseForHostChange() }
    func reserveClose(approval: DocumentCloseApproval, isHostSettled: Bool) -> Bool {
        base.reserveClose(approval: approval, isHostSettled: isHostSettled)
    }

    func releaseCloseReservation(_ approval: DocumentCloseApproval) { base.releaseCloseReservation(approval) }
    func invalidate() {
        invalidations += 1
        base.invalidate()
    }
}

@MainActor
private final class DocumentPolicyObservedModel: ObservableObject {
    @Published var revision = 0
    var builtRevisions: [Int] = []
    var onBuild: (@MainActor () -> Void)?
}

@MainActor
private struct DocumentPolicyObservedContent: View {
    @ObservedObject var model: DocumentPolicyObservedModel

    var body: some View {
        model.builtRevisions.append(model.revision)
        model.onBuild?()
        return Color.white.frame(width: 120, height: 80)
    }
}

@MainActor
private func documentPolicyConfiguration(
    model: DocumentPolicyObservedModel, isDirty: Bool = true
) throws -> (
    configuration: WindowGroupConfiguration, context: DocumentWindowContext,
    session: DocumentPolicySessionSpy, files: DocumentHostingFiles
) {
    var configuration = DocumentGroup(newDocument: DemoPlainTextDocument(text: "A")) { _ in
        DocumentPolicyObservedContent(model: model)
    }.makeWindowConfiguration()
    let descriptor = try XCTUnwrap(configuration.documentScene)
    let owner = DocumentOwnerLease()
    let files = DocumentHostingFiles()
    let dependencies = DocumentSessionDependencies(owner: owner, files: files, undoManager: nil)
    let base: any AnyDocumentSession
    if isDirty {
        let makeNew = try XCTUnwrap(descriptor.makeNew)
        base = try makeNew(.utf8PlainText, dependencies)
    } else {
        // Decode supplied bytes without reading, writing, or creating this URL.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-windowsui-close-prefix-\(Foundation.UUID().uuidString).txt")
        base = try descriptor.read(Data("A".utf8), url, .utf8PlainText, dependencies)
    }
    let session = DocumentPolicySessionSpy(base)
    let context = DocumentWindowContext(
        descriptor: descriptor, owner: owner, session: session,
        services: .headless(files: files, makeUndoManager: { nil }), undoManager: nil,
        sceneStorageScope: "document-policy:\(Foundation.UUID().uuidString)"
    )
    configuration.documentWindowContext = context
    return (configuration, context, session, files)
}

@MainActor
private func documentPolicyHost(
    configuration: WindowGroupConfiguration, renderer: FakeRenderBackend
) -> WinSwiftUIWindowHost {
    WinSwiftUIWindowHost(
        configuration: configuration, renderer: renderer, batchRenderer: nil,
        surfaceDescriptorProvider: { _ in
            SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1))!,
                pixelSize: IntSize(width: 640, height: 480), scaleFactor: 1
            )
        },
        startupProbeConfiguration: nil
    )
}

extension DocumentGroupHostingTests {
    func testQueuedObservedRebuildTeardownRejectsCloseBeforeCallingTheDocumentSession() async throws {
        try await MainActor.run {
            for isDirty in [false, true] {
                let model = DocumentPolicyObservedModel()
                let prepared = try documentPolicyConfiguration(model: model, isDirty: isDirty)
                let renderer = FakeRenderBackend()
                let host = documentPolicyHost(configuration: prepared.configuration, renderer: renderer)
                defer {
                    model.onBuild = nil
                    host.windowWillClose(host.platformWindow)
                }
                var closedCallbacks = 0
                host.onWindowClosed = { _ in closedCallbacks += 1 }
                host.windowDidCreate(host.platformWindow)
                XCTAssertFalse(host.isClosed)
                XCTAssertTrue(host.documentContext === prepared.context)
                XCTAssertEqual(prepared.session.isDirty, isDirty)
                XCTAssertEqual(prepared.session.closePhase, .idle)
                XCTAssertEqual(renderer.attachedSurfaces.count, 1)
                XCTAssertEqual(renderer.detachCount, 0)
                let initialRevisions = model.builtRevisions
                XCTAssertFalse(initialRevisions.isEmpty)
                XCTAssertTrue(initialRevisions.allSatisfy { $0 == 0 })
                let scheduledBefore = host.scheduledReloadCount
                let framesBefore = renderer.renderedFrames.count
                XCTAssertGreaterThan(framesBefore, 0)
                model.onBuild = { [weak host] in
                    guard let host else { return }
                    host.windowWillClose(host.platformWindow)
                }

                // No yield or render may consume the observed batch before the
                // direct close query executes its synchronous prefix flush.
                model.revision = 1
                XCTAssertEqual(host.scheduledReloadCount, scheduledBefore + 1)
                XCTAssertEqual(model.builtRevisions, initialRevisions)
                XCTAssertFalse(host.isClosed)
                XCTAssertFalse(host.windowShouldClose(host.platformWindow))

                XCTAssertEqual(model.builtRevisions, initialRevisions + [1])
                XCTAssertTrue(host.isClosed)
                XCTAssertFalse(prepared.context.owner.isValid)
                XCTAssertEqual(prepared.session.closeRequests, 0)
                XCTAssertEqual(prepared.session.invalidations, 1)
                XCTAssertEqual(prepared.session.closePhase, .closed)
                XCTAssertNil(prepared.session.pendingCloseIntent)
                XCTAssertNil(prepared.session.closeApproval)
                XCTAssertEqual(closedCallbacks, 1)
                XCTAssertEqual(renderer.detachCount, 1)
                XCTAssertEqual(renderer.renderedFrames.count, framesBefore)
                XCTAssertEqual(prepared.files.openChoices, 0)
                XCTAssertEqual(prepared.files.saveChoices, 0)
                XCTAssertEqual(prepared.files.reads, 0)
                XCTAssertEqual(prepared.files.writes, 0)
                XCTAssertNil(host.platformWindow.nativeHandle)
                XCTAssertNil(host.platformWindow.activeCloseAttempt)

                XCTAssertFalse(host.windowShouldClose(host.platformWindow))
                host.windowWillClose(host.platformWindow)
                XCTAssertEqual(prepared.session.closeRequests, 0)
                XCTAssertEqual(prepared.session.invalidations, 1)
                XCTAssertEqual(renderer.detachCount, 1)
                XCTAssertEqual(closedCallbacks, 1)
            }
        }
    }

    func testPartialDocumentMetadataRejectsBeforeClaimWithoutRevokingThePreparedOwner() async throws {
        try await MainActor.run {
            for hasDescriptor in [false, true] {
                let model = DocumentPolicyObservedModel()
                let prepared = try documentPolicyConfiguration(model: model)
                var malformed = prepared.configuration
                if hasDescriptor {
                    malformed.isDocumentGroup = false
                } else {
                    malformed.documentScene = nil
                }
                let renderer = FakeRenderBackend()
                let rejected = documentPolicyHost(configuration: malformed, renderer: renderer)
                defer { rejected.windowWillClose(rejected.platformWindow) }

                XCTAssertTrue(rejected.isClosed)
                XCTAssertEqual(
                    rejected.documentActivationError as? WindowCoordinatorError, .nativeDocumentActivationUnavailable)
                XCTAssertNil(rejected.documentContext)
                XCTAssertNil(prepared.context.host)
                XCTAssertTrue(prepared.context.owner.isValid)
                XCTAssertEqual(prepared.context.owner.generation, 0)
                XCTAssertNil(prepared.context.owner.runtime)
                XCTAssertEqual(prepared.session.contentCalls, 0)
                XCTAssertEqual(prepared.session.closeRequests, 0)
                XCTAssertEqual(prepared.session.invalidations, 0)
                XCTAssertEqual(prepared.session.closePhase, .idle)
                XCTAssertTrue(model.builtRevisions.isEmpty)
                XCTAssertTrue(renderer.attachedSurfaces.isEmpty)
                XCTAssertTrue(renderer.renderedFrames.isEmpty)
                XCTAssertNil(rejected.platformWindow.nativeHandle)
                XCTAssertNil(rejected.platformWindow.activeCloseAttempt)
                XCTAssertThrowsError(try rejected.validateNativeActivation()) {
                    XCTAssertEqual($0 as? WindowCoordinatorError, .nativeDocumentActivationUnavailable)
                }

                // Reusing the original complete configuration proves rejection
                // neither claimed nor revoked the prepared owner's capability.
                let admitted = documentPolicyHost(
                    configuration: prepared.configuration, renderer: FakeRenderBackend())
                defer { admitted.windowWillClose(admitted.platformWindow) }
                XCTAssertFalse(admitted.isClosed)
                XCTAssertNil(admitted.documentActivationError)
                XCTAssertTrue(admitted.documentContext === prepared.context)
                XCTAssertTrue(prepared.context.host === admitted)
                XCTAssertTrue(prepared.context.owner.isValid)
                XCTAssertTrue(prepared.context.owner.runtime === admitted.hostedRuntime)
                XCTAssertGreaterThan(prepared.session.contentCalls, 0)
                XCTAssertFalse(model.builtRevisions.isEmpty)
                XCTAssertEqual(prepared.session.invalidations, 0)
                XCTAssertEqual(prepared.files.openChoices, 0)
                XCTAssertEqual(prepared.files.saveChoices, 0)
                XCTAssertEqual(prepared.files.reads, 0)
                XCTAssertEqual(prepared.files.writes, 0)
                XCTAssertNil(admitted.platformWindow.nativeHandle)
            }
        }
    }

    func testBareDocumentMarkerKeepsRawHeadlessHostAliveWithoutAuthorizingNativeClose() async throws {
        await MainActor.run { () throws(Never) -> Void in
            let model = DocumentPolicyObservedModel()
            let renderer = FakeRenderBackend()
            let configuration = WindowGroupConfiguration(
                title: "Unadapted document marker", size: IntSize(width: 640, height: 480),
                clearColor: .white, content: [AnyView(DocumentPolicyObservedContent(model: model))],
                isDocumentGroup: true
            )
            XCTAssertNil(configuration.documentScene)
            XCTAssertNil(configuration.documentWindowContext)
            let host = documentPolicyHost(configuration: configuration, renderer: renderer)
            defer { host.windowWillClose(host.platformWindow) }
            var closedCallbacks = 0
            host.onWindowClosed = { _ in closedCallbacks += 1 }
            host.windowDidCreate(host.platformWindow)

            XCTAssertFalse(host.isClosed)
            XCTAssertNil(host.documentActivationError)
            XCTAssertNil(host.documentContext)
            XCTAssertFalse(model.builtRevisions.isEmpty)
            XCTAssertEqual(renderer.attachedSurfaces.count, 1)
            XCTAssertFalse(renderer.renderedFrames.isEmpty)
            XCTAssertFalse(host.windowShouldClose(host.platformWindow))
            XCTAssertThrowsError(try host.validateNativeActivation()) {
                XCTAssertEqual($0 as? WindowCoordinatorError, .nativeDocumentActivationUnavailable)
            }
            XCTAssertFalse(host.isClosed)
            XCTAssertEqual(renderer.detachCount, 0)
            XCTAssertEqual(closedCallbacks, 0)
            XCTAssertNil(host.platformWindow.nativeHandle)
            XCTAssertNil(host.platformWindow.activeCloseAttempt)
        }
    }
}

extension DocumentGroupHostingTests {
    func testBuiltInPlatformHooksRejectHeadlessDocumentMetadataBeforeNativeStartup() async throws {
        try await MainActor.run {
            let platform = DocumentHostingRefusingPlatform()
            let files = DocumentHostingFiles()
            let model = DocumentPolicyObservedModel()
            var created: [WinSwiftUIWindowHost] = []
            defer {
                for host in created { host.windowWillClose(host.platformWindow) }
            }
            let factory: @MainActor (WindowGroupConfiguration, Bool) throws -> WinSwiftUIWindowHost = {
                configuration, _ in
                let host = documentPolicyHost(configuration: configuration, renderer: FakeRenderBackend())
                created.append(host)
                return host
            }
            let documentConfiguration = DocumentGroup(newDocument: DemoPlainTextDocument(text: "A")) { _ in
                DocumentPolicyObservedContent(model: model)
            }.makeWindowConfiguration()
            let coordinator = WinSwiftUIWindowCoordinator(
                sceneConfigurations: [documentConfiguration], platformHostFactory: platform,
                hooks: .platform(platform), hostFactory: factory,
                documentServices: .headless(files: files, makeUndoManager: { nil })
            )

            // Explicitly supplying built-in hooks is not permission to start a
            // native document. Even a regressed guard reaches only this throwing
            // factory, never create(), a dialog, or an operating-system loop.
            XCTAssertThrowsError(try coordinator.bootPrimaryWindow()) {
                XCTAssertEqual($0 as? WindowCoordinatorError, .nativeDocumentActivationUnavailable)
            }
            XCTAssertEqual(created.count, 1)
            let rejected = try XCTUnwrap(created.first)
            let context = try XCTUnwrap(rejected.documentContext)
            XCTAssertFalse(model.builtRevisions.isEmpty, "A real typed context must reach the startup boundary.")
            XCTAssertTrue(rejected.isClosed)
            XCTAssertFalse(context.owner.isValid)
            XCTAssertEqual(context.session.closePhase, .closed)
            XCTAssertEqual(coordinator.windowCount, 0)
            XCTAssertEqual(platform.makeCalls, 0)
            XCTAssertEqual(platform.startCalls, 0)
            XCTAssertEqual(platform.loopCalls, 0)
            XCTAssertNil(rejected.platformWindow.nativeHandle)
            XCTAssertNil(rejected.platformWindow.activeCloseAttempt)
            XCTAssertEqual(files.openChoices, 0)
            XCTAssertEqual(files.saveChoices, 0)
            XCTAssertEqual(files.reads, 0)
            XCTAssertEqual(files.writes, 0)

            // Ordinary windows still reach the existing platform start seam.
            // Its injected throw keeps this positive control noncreating too.
            let ordinary = WinSwiftUIWindowCoordinator(
                sceneConfigurations: [
                    WindowGroup("Ordinary platform startup") {
                        Color.white.frame(width: 120, height: 80)
                    }.makeWindowConfiguration()
                ],
                platformHostFactory: platform, hooks: .platform(platform), hostFactory: factory
            )
            XCTAssertThrowsError(try ordinary.bootPrimaryWindow()) {
                XCTAssertEqual($0 as? DocumentHostingError, .injected)
            }
            XCTAssertEqual(created.count, 2)
            let ordinaryHost = try XCTUnwrap(created.last)
            XCTAssertNil(ordinaryHost.documentContext)
            XCTAssertTrue(ordinaryHost.isClosed)
            XCTAssertEqual(ordinary.windowCount, 0)
            XCTAssertEqual(platform.makeCalls, 0)
            XCTAssertEqual(platform.startCalls, 1)
            XCTAssertEqual(platform.loopCalls, 0)
            XCTAssertNil(ordinaryHost.platformWindow.nativeHandle)
            XCTAssertNil(ordinaryHost.platformWindow.activeCloseAttempt)
        }
    }
}
