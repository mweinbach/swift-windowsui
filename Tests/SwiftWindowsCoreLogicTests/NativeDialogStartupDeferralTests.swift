import Foundation
import SwiftWindowsCore
import Synchronization
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class StartupDialogProvider: NativeOwnerFileDialogProvider {
    let supportsNativeOwnerRequests = true
    var openCount = 0
    var saveCount = 0
    var legacySelection: [URL] = []

    func showOpenFileDialog(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool, defaultDirectory: URL?, title: String?
    ) -> [URL] {
        openCount += 1
        return legacySelection
    }

    func showSaveFileDialog(
        defaultFilename: String?, allowedExtensions: [String]?, defaultDirectory: URL?, title: String?
    ) -> URL? {
        saveCount += 1
        return nil
    }
}

/// Records actual production commands but never executes their native body.
private final class StartupDialogSink: NativeWindowCommandSink {
    private let commands = Mutex<[any NativeWindowOwnerCommand]>([])
    var count: Int { commands.withLock { $0.count } }

    func command(at index: Int) -> (any NativeWindowOwnerCommand)? {
        commands.withLock { $0.indices.contains(index) ? $0[index] : nil }
    }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        commands.withLock { $0.append(command) }
        return .accepted
    }
}

@MainActor
private final class StartupImporterFixture {
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    var presented = false
    var resets = 0
    var results: [Result<URL, Error>] = []
    var onCompletion: (() -> Void)?

    init(expectsNativeOwner: Bool = true) {
        runtime = RetainedViewRuntime(root: ViewNode())
        host = ComponentHost(runtime: runtime)
        host.expectsNativeDialogOwner = expectsNativeOwner
        runtime.setRootSize(IntSize(width: 320, height: 240))
        host.setComponents { [weak self] in
            guard let self else { return [] }
            let context = ViewBuildContext(
                nativeDialogSession: self.host.nativeDialogSession,
                canvasSizeProvider: { Size(width: 320, height: 240) }, invalidateHandler: {})
            let binding = Binding(
                get: { self.presented },
                set: { value in
                    if self.presented, !value { self.resets += 1 }
                    self.presented = value
                })
            return [
                Text("Pending importer").fileImporter(isPresented: binding, allowedContentTypes: [.plainText]) {
                    self.results.append($0)
                    self.onCompletion?()
                }.makeComponent(context: context)
            ]
        }
    }

    func triggerFromActorTask() async {
        await Task { @MainActor [self] in
            presented = true
            host.reload(onCompleted: { self.host.processPendingFileDialogs() })
        }.value
    }

    func bind(_ session: NativeDialogSession) {
        host.nativeDialogSession = session
        host.reload(onCompleted: { self.host.processPendingFileDialogs() })
    }

    func cleanUp() {
        host.invalidateFileDialogRequests()
        host.nativeDialogSession?.invalidate()
        host.setComponents { [] }
    }
}

@MainActor
private final class StartupImporterModel: ObservableObject {
    @Published var presented = false
    var results: [Result<URL, Error>] = []
}

@MainActor
private struct StartupImporterView: View {
    @ObservedObject var model: StartupImporterModel

    var body: some View {
        Text(model.presented ? "Requested" : "Idle")
            .fileImporter(
                isPresented: Binding(get: { model.presented }, set: { model.presented = $0 }),
                allowedContentTypes: [.plainText]
            ) { model.results.append($0) }
    }
}

@MainActor
private final class StartupDialogBuildProbe {
    var context: ViewBuildContext?
    var duringBuild: ((ViewBuildContext) -> Void)?
}

@MainActor
private struct StartupDialogBuildProbeView: View {
    typealias Body = Never
    let probe: StartupDialogBuildProbe
    var body: Never { fatalError("StartupDialogBuildProbeView has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        probe.context = context
        probe.duringBuild?(context)
        return Text("Dialog owner readiness").makeComponent(context: context)
    }
}

@MainActor
final class NativeDialogStartupDeferralTests: XCTestCase {
    func testSupersededSessionBindReleasesPendingActionsAfterLaterAdoption() async throws {
        let factory = try XCTUnwrap(SoftwareWindowRenderBackendFactory().makeNativePresentationFactory())
        let probe = StartupDialogBuildProbe()
        let windowHost = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Superseded native binding", size: IntSize(width: 320, height: 240), clearColor: .black,
                content: [AnyView(StartupDialogBuildProbeView(probe: probe))]),
            nativePresentationFactory: factory, startupProbeConfiguration: nil)
        let originalContext = try XCTUnwrap(probe.context)
        var events: [String] = []
        var deliveredSession: NativeDialogSession?
        originalContext.withNativeDialogOwner { session in
            deliveredSession = session
            events.append("delivered")
        }
        XCTAssertNil(deliveredSession)
        XCTAssertTrue(events.isEmpty)

        let sink = StartupDialogSink()
        let session = NativeDialogSession(windowKey: NativeWindowKey(), commandSink: sink)
        var mustSupersede = true
        probe.duringBuild = { context in
            XCTAssertTrue(context.nativeDialogSession === session)
            if mustSupersede {
                mustSupersede = false
                events.append("superseded")
                context.invalidate()
            } else {
                events.append("replacement")
            }
        }

        // This is the production binding/rebuild path with a captured command
        // sink. No window is created and no native command body is executed.
        windowHost.bindNativeDialogSession(session)

        XCTAssertEqual(events, ["superseded", "replacement", "delivered"])
        XCTAssertTrue(deliveredSession === session)
        XCTAssertNil(windowHost.platformWindow.nativeHandle)
        XCTAssertEqual(sink.count, 0)
        probe.duringBuild = nil
        probe.context = nil
        try await windowHost.discardNativeFailedStartup()
        XCTAssertFalse(session.isValid)
    }

    func testActorTaskDuringHeldNativeStartDoesNotCallLegacyProvider() async throws {
        let previous = FileDialogManager.provider
        let provider = StartupDialogProvider()
        FileDialogManager.provider = provider
        defer { FileDialogManager.provider = previous }
        let model = StartupImporterModel()
        let factory = try XCTUnwrap(SoftwareWindowRenderBackendFactory().makeNativePresentationFactory())
        let windowHost = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Held native startup", size: IntSize(width: 320, height: 240), clearColor: .black,
                content: [AnyView(StartupImporterView(model: model))]),
            nativePresentationFactory: factory, startupProbeConfiguration: nil)
        let reloaded = expectation(description: "task mutation rebuilt retained content")
        windowHost.onReloadContentCompleted = { reloaded.fulfill() }

        await Task { @MainActor in model.presented = true }.value
        let completion = await XCTWaiter.fulfillment(of: [reloaded], timeout: 2)
        windowHost.onReloadContentCompleted = nil

        XCTAssertEqual(completion, .completed)
        XCTAssertNil(windowHost.platformWindow.nativeHandle)
        XCTAssertTrue(model.presented, "A missing native owner must not cancel the pending request.")
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(provider.openCount, 0)
        XCTAssertEqual(provider.saveCount, 0)
        try await windowHost.discardNativeFailedStartup()
    }

    func testPendingImporterStartsOneNativeCommandAfterOwnerBindAndRebuild() async throws {
        let previous = FileDialogManager.provider
        let provider = StartupDialogProvider()
        FileDialogManager.provider = provider
        defer { FileDialogManager.provider = previous }
        let fixture = StartupImporterFixture()
        defer { fixture.cleanUp() }

        await fixture.triggerFromActorTask()
        fixture.host.processPendingFileDialogs()
        fixture.host.processPendingFileDialogs()
        XCTAssertTrue(fixture.presented)
        XCTAssertEqual(fixture.resets, 0)
        XCTAssertTrue(fixture.results.isEmpty)
        XCTAssertEqual(provider.openCount, 0)
        XCTAssertEqual(provider.saveCount, 0)

        let key = NativeWindowKey()
        let sink = StartupDialogSink()
        let session = NativeDialogSession(windowKey: key, commandSink: sink)
        let finished = expectation(description: "actual command reply delivered")
        fixture.onCompletion = { finished.fulfill() }
        fixture.bind(session)
        fixture.host.processPendingFileDialogs()

        XCTAssertEqual(sink.count, 1)
        XCTAssertTrue(session.hasPendingRequests)
        XCTAssertTrue(fixture.presented, "Native admission is not dialog completion.")
        XCTAssertEqual(fixture.resets, 0)
        XCTAssertEqual(provider.openCount, 0)
        let command = try XCTUnwrap(sink.command(at: 0) as? NativeDialogCommand)
        XCTAssertEqual(command.windowKey, key)
        guard case .openFile(let extensions, let multiple, _, _) = command.request else {
            return XCTFail("The retained pending importer must become an owned open-file command.")
        }
        XCTAssertEqual(extensions, ["txt"])
        XCTAssertFalse(multiple)

        // A value reply exercises delivery without fabricating an HWND or
        // opening a native dialog. Only transport and retained state are tested.
        let selected = URL(fileURLWithPath: "C:/dialog-fixture/startup.txt")
        command.reply.complete(.success(.selectedFiles([selected])))
        let completion = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(completion, .completed)
        XCTAssertEqual(try fixture.results.map { try $0.get() }, [selected])
        XCTAssertFalse(fixture.presented)
        XCTAssertEqual(fixture.resets, 1)
        XCTAssertFalse(session.hasPendingRequests)
        XCTAssertEqual(sink.count, 1)
        XCTAssertEqual(provider.openCount, 0)
    }

    func testRetirementWhileWaitingDoesNotReviveTheRequestOnOwnerBind() async {
        let previous = FileDialogManager.provider
        let provider = StartupDialogProvider()
        FileDialogManager.provider = provider
        defer { FileDialogManager.provider = previous }
        let fixture = StartupImporterFixture()
        defer { fixture.cleanUp() }
        await fixture.triggerFromActorTask()
        fixture.host.invalidateFileDialogRequests()
        let sink = StartupDialogSink()
        fixture.bind(NativeDialogSession(windowKey: NativeWindowKey(), commandSink: sink))
        XCTAssertEqual(sink.count, 0)
        XCTAssertEqual(provider.openCount, 0)
        XCTAssertTrue(fixture.presented)
        XCTAssertEqual(fixture.resets, 0)
        XCTAssertTrue(fixture.results.isEmpty)
    }

    func testLegacyHostStillUsesInjectedProviderWithoutOwnerExpectation() async throws {
        let previous = FileDialogManager.provider
        let provider = StartupDialogProvider()
        let selected = URL(fileURLWithPath: "C:/dialog-fixture/legacy.txt")
        provider.legacySelection = [selected]
        FileDialogManager.provider = provider
        defer { FileDialogManager.provider = previous }
        let fixture = StartupImporterFixture(expectsNativeOwner: false)
        defer { fixture.cleanUp() }
        await fixture.triggerFromActorTask()
        XCTAssertEqual(provider.openCount, 1)
        XCTAssertEqual(try fixture.results.map { try $0.get() }, [selected])
        XCTAssertFalse(fixture.presented)
        XCTAssertEqual(fixture.resets, 1)
    }
}
