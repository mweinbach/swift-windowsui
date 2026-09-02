import Foundation
import SwiftWindowsCore
import SwiftWindowsDemo
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class OwnedRootViewContentTests: XCTestCase {
    func testDirectListRootAcceptsDeletionBeforeSameKeyReinsertionInsideItsRowAction() async throws {
        let probe = OwnedRootContentProbe()
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) { probe.makeRows() }
        defer {
            probe.onAction = nil
            host.close()
        }
        XCTAssertNotNil(host.layout())
        let button = try ownedRootButton(in: host.runtime)
        let list = try host.list()
        let original = try XCTUnwrap(host.runtime.lazyListAccessibilityItem(in: list, containing: button))
        var acceptedAbsences = 0
        probe.onAction = {
            probe.rows.removeAll { $0 == 0 }
            host.reload()
            XCTAssertFalse(host.runtime.isLazyListAccessibilityTokenCurrent(original.token, in: original))
            acceptedAbsences += 1
            probe.rows.insert(0, at: 0)
            host.reload()
            XCTAssertFalse(host.runtime.isLazyListAccessibilityTokenCurrent(original.token, in: original))
        }

        button.onActivate?()

        XCTAssertEqual(probe.actions, 1)
        XCTAssertEqual(acceptedAbsences, 1)
        XCTAssertFalse(host.runtime.isLazyListAccessibilityTokenCurrent(original.token, in: original))
        XCTAssertNotNil(host.layout())
        let replacement = try XCTUnwrap(
            host.runtime.lazyListAccessibilityItem(in: try host.list(), containing: ownedRootButton(in: host.runtime)))
        XCTAssertNotEqual(replacement.token, original.token)
        XCTAssertTrue(host.runtime.isLazyListAccessibilityTokenCurrent(replacement.token, in: replacement))
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
    }

    func testMountedMetadataOwnerCloseRejectsTheCandidateWithoutPublishingAnEmptyRoot() async throws {
        let probe = OwnedRootKeyProbe()
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) { probe.makeRows() }
        defer {
            probe.onHash = nil
            host.close()
        }
        XCTAssertNotNil(host.layout())
        let originalRoots = host.runtime.root.children
        let completions = host.events.rootCompletions
        let bodies = probe.rowBodies
        probe.onHash = { host.coordinator.close() }

        host.reload()

        XCTAssertEqual(probe.interventions, 1)
        XCTAssertEqual(host.events.rootCompletions, completions)
        XCTAssertEqual(probe.rowBodies, bodies)
        XCTAssertEqual(host.runtime.root.children.count, originalRoots.count)
        XCTAssertTrue(zip(host.runtime.root.children, originalRoots).allSatisfy { $0.0 === $0.1 })
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
    }

    func testSupersededMetadataCannotCommitAbsenceBeforeTheQueuedIndependentRoot() async throws {
        let probe = OwnedRootKeyProbe()
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) { probe.makeRows() }
        defer {
            probe.onHash = nil
            probe.onRoot = nil
            host.close()
        }
        XCTAssertNotNil(host.layout())
        let list = try host.list()
        let originalNode = try XCTUnwrap(host.find("owned.key.0"))
        let original = try XCTUnwrap(host.runtime.lazyListAccessibilityItem(in: list, containing: originalNode))
        let completions = host.events.rootCompletions
        let firstRootCalls = probe.rootCalls
        var successorEntries = 0
        probe.rows.removeAll { $0 == 0 }
        probe.onHash = {
            probe.rows.insert(0, at: 0)
            host.reload()
        }
        probe.onRoot = {
            guard probe.rootCalls == firstRootCalls + 2 else { return }
            successorEntries += 1
            XCTAssertEqual(host.events.rootCompletions, completions)
            XCTAssertTrue(host.runtime.isLazyListAccessibilityTokenCurrent(original.token, in: original))
        }

        host.reload()

        XCTAssertEqual(probe.interventions, 1)
        XCTAssertEqual(successorEntries, 1)
        XCTAssertEqual(probe.rootCalls, firstRootCalls + 2)
        XCTAssertEqual(host.events.rootCompletions, completions + 1)
        XCTAssertTrue(host.runtime.isLazyListAccessibilityTokenCurrent(original.token, in: original))
        XCTAssertNotNil(host.layout())
        XCTAssertNotNil(host.find("owned.key.0"))
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
    }

    func testMountedMetadataDescriptorDoesNotEscapeIntoLaterRowConstruction() async throws {
        let probe = OwnedRootContentProbe()
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) { probe.makeRows() }
        defer { host.close() }
        XCTAssertEqual(probe.rootCalls, 1)
        XCTAssertEqual(probe.mountedRootContexts, 1)
        XCTAssertNil(probe.metadataDescriptor)
        XCTAssertNotNil(host.layout())
        XCTAssertGreaterThan(probe.rowBodies, 0)
        XCTAssertEqual(probe.rowBodies, probe.enteredRowContexts)
        XCTAssertNil(probe.metadataDescriptor)
        try host.assertCommittedDescriptor()
    }

    func testNativeDefaultFactoryFromAnExpiredRowUsesTheOriginalNewWindowRequest() async throws {
        try await assertNativeFactoryFromRow(valueBased: false)
    }

    func testNativeDataBoundFactoryFromAnExpiredRowPreservesItsPayloadAndDeduplication() async throws {
        try await assertNativeFactoryFromRow(valueBased: true)
    }

    func testNativeRootCallbackClosingItsOriginalOwnerCannotPublishOrEnterTheHostFactory() async throws {
        for valueBased in [false, true] {
            let probe = OwnedRootContentProbe()
            let driver = OwnedRootWindowDriver()
            let coordinator = makeOwnedRootNativeCoordinator(probe: probe, driver: driver, valueBased: valueBased)
            let run = Task { @MainActor in try await coordinator.runNative() }
            defer {
                driver.closeAll(coordinator)
                run.cancel()
            }
            let primary = await driver.observeStart()
            _ = try await coordinator.bootPrimaryNativeWindow()
            let source = OwnedRootContentProbe()
            let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) { source.makeRows() }
            defer {
                source.onAction = nil
                probe.onRoot = nil
                host.close()
            }
            XCTAssertNotNil(host.layout())
            let open = try XCTUnwrap(primary.windowEnvironment).openWindow
            probe.onRoot = { coordinator.dismissWindow(payload: WindowActionPayload(), from: primary) }
            source.onAction = {
                if valueBased { open(id: "owned.destination", value: 7) } else { open(id: "owned.destination") }
            }

            try ownedRootButton(in: host.runtime).onActivate?()

            XCTAssertEqual(source.actions, 1)
            XCTAssertEqual(probe.rootCalls, 1)
            XCTAssertEqual(probe.nativeRootContexts, 1)
            XCTAssertEqual(driver.factoryCalls, 1)
            XCTAssertEqual(coordinator.windowCount, 0)
            XCTAssertEqual(driver.discards, 0)
            let exitCode = try await run.value
            XCTAssertEqual(exitCode, 0)
            XCTAssertEqual(driver.ownerStops, 1)
        }
    }

    func testReentrantNativeFactoryCannotReplaceTheOriginalPreparation() async throws {
        let probe = OwnedRootContentProbe()
        let driver = OwnedRootWindowDriver()
        let coordinator = makeOwnedRootNativeCoordinator(probe: probe, driver: driver, valueBased: false)
        let run = Task { @MainActor in try await coordinator.runNative() }
        defer {
            probe.onRoot = nil
            driver.closeAll(coordinator)
            run.cancel()
        }
        let primary = await driver.observeStart()
        _ = try await coordinator.bootPrimaryNativeWindow()
        var rejections = 0
        probe.onRoot = {
            do {
                _ = try coordinator.beginNativeWindowRequest(payload: WindowActionPayload(id: "main"))
                XCTFail("Expected the original preparation's reentry rejection")
            } catch {
                guard case NativeWindowCoordinatorError.reentrantWindowPreparation = error else {
                    return XCTFail("Expected the original preparation's reentry rejection, got \(error)")
                }
                rejections += 1
            }
        }
        let open = try XCTUnwrap(primary.windowEnvironment).openWindow

        open(id: "owned.destination")

        XCTAssertEqual(rejections, 1)
        XCTAssertEqual(probe.rootCalls, 1)
        XCTAssertEqual(driver.factoryCalls, 2)
        XCTAssertEqual(coordinator.windowCount, 2)
        let destination = await driver.observeStart()
        XCTAssertNotNil(destination.hostedRuntime.resolvedLayoutFrame(of: destination.hostedRuntime.root))
        XCTAssertNotNil(
            ownedRootNodes(destination.hostedRuntime.root).first { $0.accessibilityIdentifier == "owned.root.0" })
        driver.closeAll(coordinator)
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 0)
    }

    func testDocumentRootReevaluatesItsDirectListInsideARealRetainedRowAction() async throws {
        let probe = OwnedRootContentProbe()
        let driver = OwnedRootWindowDriver()
        let coordinator = makeOwnedRootDocumentCoordinator(probe: probe, driver: driver)
        let host = try coordinator.bootPrimaryWindow()
        defer {
            probe.onAction = nil
            driver.closeAll(coordinator)
        }
        let runtime = host.hostedRuntime
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let list = try XCTUnwrap(ownedRootNodes(runtime.root).first { $0.retainedLazyListAdapter != nil })
        let removedNode = try XCTUnwrap(
            ownedRootNodes(runtime.root).first { $0.accessibilityIdentifier == "owned.root.1" })
        let removed = try XCTUnwrap(runtime.lazyListAccessibilityItem(in: list, containing: removedNode))
        let document = try XCTUnwrap(probe.document)
        let rootCalls = probe.rootCalls
        probe.onAction = {
            probe.rows.removeAll { $0 == 1 }
            document.wrappedValue = DemoPlainTextDocument(text: "second revision")
        }

        try ownedRootButton(in: runtime).onActivate?()

        XCTAssertEqual(probe.actions, 1)
        XCTAssertGreaterThan(probe.rootCalls, rootCalls)
        XCTAssertEqual(probe.rootCalls, probe.mountedRootContexts)
        XCTAssertFalse(runtime.isLazyListAccessibilityTokenCurrent(removed.token, in: removed))
        XCTAssertTrue(try XCTUnwrap(host.documentContext).owner.isValid)
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        XCTAssertNil(ownedRootNodes(runtime.root).first { $0.accessibilityIdentifier == "owned.root.1" })
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
    }

    func testDocumentOwnerRevocationDuringRootContentDoesNotPublishAnEmptyReplacement() async throws {
        let probe = OwnedRootContentProbe()
        let driver = OwnedRootWindowDriver()
        let coordinator = makeOwnedRootDocumentCoordinator(probe: probe, driver: driver)
        let host = try coordinator.bootPrimaryWindow()
        defer {
            probe.onAction = nil
            probe.onRoot = nil
            driver.closeAll(coordinator)
        }
        let runtime = host.hostedRuntime
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let originalRoots = runtime.root.children
        let document = try XCTUnwrap(probe.document)
        let context = try XCTUnwrap(host.documentContext)
        let calls = probe.rootCalls
        let bodies = probe.rowBodies
        probe.onRoot = { context.owner.revoke() }
        probe.onAction = { document.wrappedValue = DemoPlainTextDocument(text: "revoked revision") }

        try ownedRootButton(in: runtime).onActivate?()

        XCTAssertEqual(probe.actions, 1)
        XCTAssertEqual(probe.rootCalls, calls + 1)
        XCTAssertFalse(context.owner.isValid)
        XCTAssertEqual(probe.rowBodies, bodies)
        XCTAssertEqual(runtime.root.children.count, originalRoots.count)
        XCTAssertTrue(zip(runtime.root.children, originalRoots).allSatisfy { $0.0 === $0.1 })
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
    }

    func testRootValueContextCopiesProvidersWithoutReadingThemAndRestoresTheCaller() async {
        var environmentReads = 0
        let outer = ViewBuildContext(
            canvasSizeProvider: { Size(width: 321, height: 87) }, invalidateHandler: {},
            environmentValuesProvider: {
                environmentReads += 1
                return EnvironmentValues(colorScheme: .dark)
            }
        ).withViewIdentityPrefix([.slot(17)])
        let inner = outer.rootViewContentContext()
        XCTAssertEqual(environmentReads, 0)
        XCTAssertEqual(inner.retainedViewIdentity, RetainedViewIdentity())
        XCTAssertNil(inner.stateMountCoordinator)
        var current = true
        var callbacks = 0
        ViewBuildContextScope.withCurrent(outer) {
            let result = evaluateRootViewContent(in: inner, while: { current }) {
                callbacks += 1
                XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, RetainedViewIdentity())
                XCTAssertEqual(Environment<ColorScheme>(\.colorScheme).wrappedValue, .dark)
                current = false
                return Text("must not publish")
            }
            if case .value = result { XCTFail("A lost original owner must not return content") }
            XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, outer.retainedViewIdentity)
            _ = evaluateRootViewContent(in: inner, while: { current }) { callbacks += 1 }
        }
        XCTAssertEqual(callbacks, 1)
        // Reading environmentValues also resolves isEnabled from the same
        // provider. The context copy and rejected second entry read neither.
        XCTAssertEqual(environmentReads, 2)
        XCTAssertNil(ViewBuildContextScope.current)
    }

    private func assertNativeFactoryFromRow(valueBased: Bool) async throws {
        let probe = OwnedRootContentProbe()
        let driver = OwnedRootWindowDriver()
        let coordinator = makeOwnedRootNativeCoordinator(probe: probe, driver: driver, valueBased: valueBased)
        let run = Task { @MainActor in try await coordinator.runNative() }
        defer {
            driver.closeAll(coordinator)
            run.cancel()
        }
        let primary = await driver.observeStart()
        _ = try await coordinator.bootPrimaryNativeWindow()
        let source = OwnedRootContentProbe()
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) { source.makeRows() }
        defer {
            source.onAction = nil
            host.close()
        }
        XCTAssertNotNil(host.layout())
        let open = try XCTUnwrap(primary.windowEnvironment).openWindow
        source.onAction = {
            if valueBased { open(id: "owned.destination", value: 7) } else { open(id: "owned.destination") }
        }

        try ownedRootButton(in: host.runtime).onActivate?()

        XCTAssertEqual(source.actions, 1)
        XCTAssertEqual(source.restoredActionContexts, 1)
        XCTAssertEqual(probe.rootCalls, 1)
        XCTAssertEqual(probe.nativeRootContexts, 1)
        XCTAssertEqual(probe.payloads, valueBased ? [7] : [])
        XCTAssertEqual(driver.factoryCalls, 2)
        XCTAssertEqual(coordinator.windowCount, 2)
        let destination = await driver.observeStart()
        XCTAssertNotNil(destination.hostedRuntime.resolvedLayoutFrame(of: destination.hostedRuntime.root))
        XCTAssertNotNil(
            ownedRootNodes(destination.hostedRuntime.root).first { $0.accessibilityIdentifier == "owned.root.0" })
        XCTAssertGreaterThan(probe.rowBodies, 0)
        XCTAssertEqual(probe.rowBodies, probe.enteredRowContexts)
        if valueBased {
            let represented = try await coordinator.openNativeWindow(
                payload: WindowActionPayload(id: "owned.destination", value: 7))
            XCTAssertTrue(represented)
            XCTAssertEqual(driver.factoryCalls, 2)
            XCTAssertEqual(probe.rootCalls, 1)
            XCTAssertEqual(driver.activations, 1)
        }
        driver.closeAll(coordinator)
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 0)
    }
}

@MainActor
private final class OwnedRootContentProbe {
    var rows = Array(0..<12)
    var checksEnabled = true
    var rootCalls = 0
    var mountedRootContexts = 0
    var nativeRootContexts = 0
    var rowBodies = 0
    var enteredRowContexts = 0
    var actions = 0
    var restoredActionContexts = 0
    var payloads: [Int] = []
    weak var metadataDescriptor: RetainedDescriptorComponentAttribution?
    var document: Binding<DemoPlainTextDocument>?
    var onRoot: (() -> Void)?
    var onAction: (() -> Void)?

    func makeRows(payload: Int? = nil) -> AnyView {
        if checksEnabled {
            rootCalls += 1
            if let payload { payloads.append(payload) }
            let context = ViewBuildContextScope.current
            XCTAssertNotNil(context)
            XCTAssertNil(context?.viewIdentity.lazyList)
            XCTAssertNil(context?.viewIdentity.installedOwner)
            XCTAssertEqual(context?.retainedViewIdentity, RetainedViewIdentity())
            if let descriptor = context?.viewIdentity.descriptorComponent {
                mountedRootContexts += 1
                XCTAssertTrue(descriptor.canConstruct)
                metadataDescriptor = descriptor
            } else {
                nativeRootContexts += 1
                XCTAssertNil(context?.stateMountCoordinator)
            }
            onRoot?()
        }
        return AnyView(List(rows, id: \.self) { id in self.makeRow(id) }.listStyle(.plain))
    }

    private func makeRow(_ id: Int) -> [AnyView] {
        rowBodies += 1
        if ViewBuildContextScope.current?.viewIdentity.lazyList?.isCurrent == true { enteredRowContexts += 1 }
        return [
            AnyView(
                Button("Row \(id)") {
                    self.actions += 1
                    let original = ViewBuildContextScope.current
                    XCTAssertNotNil(original?.viewIdentity.lazyList)
                    XCTAssertFalse(original?.viewIdentity.lazyList?.isCurrent ?? true)
                    self.onAction?()
                    XCTAssertTrue(
                        ViewBuildContextScope.current?.viewIdentity.lazyList?.admission
                            === original?.viewIdentity.lazyList?.admission)
                    self.restoredActionContexts += 1
                }
                .accessibilityIdentifier("owned.root.\(id)")
                .frame(height: 24))
        ]
    }

    func makeDocumentRows(_ configuration: FileDocumentConfiguration<DemoPlainTextDocument>) -> AnyView {
        document = configuration.$document
        return makeRows()
    }
}

private struct OwnedRootKey: Hashable {
    let value: Int
    let probe: OwnedRootKeyProbe

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { probe.hashEntered() }
        hasher.combine(value)
    }
}

@MainActor
private final class OwnedRootKeyProbe {
    var rows = Array(0..<12)
    var rootCalls = 0
    var rowBodies = 0
    var interventions = 0
    var onHash: (() -> Void)?
    var onRoot: (() -> Void)?

    func hashEntered() {
        guard let callback = onHash else { return }
        onHash = nil
        interventions += 1
        XCTAssertNotNil(ViewBuildContextScope.current?.viewIdentity.descriptorComponent)
        callback()
    }

    func makeRows() -> AnyView {
        rootCalls += 1
        onRoot?()
        let values = rows.map { OwnedRootKey(value: $0, probe: self) }
        return AnyView(List(values, id: \.self) { key in self.makeRow(key) }.listStyle(.plain))
    }

    private func makeRow(_ key: OwnedRootKey) -> [AnyView] {
        rowBodies += 1
        return [AnyView(Text("Key \(key.value)").accessibilityIdentifier("owned.key.\(key.value)").frame(height: 24))]
    }
}

/// The real coordinator and retained host run with controlled native hooks.
/// No HWND, native event loop, filesystem operation, or presentation is used.
@MainActor
private final class OwnedRootWindowDriver {
    var factoryCalls = 0
    var activations = 0
    var discards = 0
    var ownerStops = 0
    private var starts: [WinSwiftUIWindowHost] = []
    private var startWaiter: CheckedContinuation<WinSwiftUIWindowHost, Never>?

    func hooks() -> WindowCoordinatorNativeHooks {
        WindowCoordinatorNativeHooks(
            startOwner: {},
            startWindow: { host, _ in
                host.windowDidCreate(host.platformWindow)
                if let waiter = self.startWaiter {
                    self.startWaiter = nil
                    waiter.resume(returning: host)
                } else {
                    self.starts.append(host)
                }
            },
            activateWindow: { _ in
                self.activations += 1
                return true
            },
            requestCloseWindow: { host in host.windowWillClose(host.platformWindow) },
            discardFailedWindow: { host in
                self.discards += 1
                host.windowWillClose(host.platformWindow)
            },
            stopOwner: {
                self.ownerStops += 1
                return 0
            })
    }

    func observeStart() async -> WinSwiftUIWindowHost {
        if !starts.isEmpty { return starts.removeFirst() }
        return await withCheckedContinuation { startWaiter = $0 }
    }

    func makeHost(_ configuration: WindowGroupConfiguration) -> WinSwiftUIWindowHost {
        factoryCalls += 1
        XCTAssertNil(configuration.windowContentFactory)
        return WinSwiftUIWindowHost(
            configuration: configuration, renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in SurfaceDescriptor(offscreenPixelSize: IntSize(width: 320, height: 80)) },
            startupProbeConfiguration: nil)
    }

    func closeAll(_ coordinator: WinSwiftUIWindowCoordinator) {
        for window in coordinator.windows { window.host.windowWillClose(window.host.platformWindow) }
    }
}

@MainActor
private func makeOwnedRootNativeCoordinator(
    probe: OwnedRootContentProbe, driver: OwnedRootWindowDriver, valueBased: Bool
) -> WinSwiftUIWindowCoordinator {
    probe.checksEnabled = false
    let destination: WindowGroupConfiguration
    if valueBased {
        destination = WindowGroup("Destination", id: "owned.destination", for: Int.self) { value in
            probe.makeRows(payload: value.wrappedValue)
        }.makeWindowConfiguration()
    } else {
        destination = WindowGroup("Destination", id: "owned.destination") { probe.makeRows() }.makeWindowConfiguration()
    }
    probe.checksEnabled = true
    return WinSwiftUIWindowCoordinator(
        sceneConfigurations: [
            WindowGroup("Primary", id: "main") { Text("Primary") }.makeWindowConfiguration(), destination,
        ],
        nativeHooks: driver.hooks(), hostFactory: { configuration, _ in driver.makeHost(configuration) })
}

@MainActor
private func makeOwnedRootDocumentCoordinator(
    probe: OwnedRootContentProbe, driver: OwnedRootWindowDriver
) -> WinSwiftUIWindowCoordinator {
    let configuration = DocumentGroup(newDocument: DemoPlainTextDocument(text: "first revision")) { document in
        probe.makeDocumentRows(document)
    }.makeWindowConfiguration()
    return WinSwiftUIWindowCoordinator(
        sceneConfigurations: [configuration],
        hooks: WindowCoordinatorHooks(
            startWindow: { host in host.windowDidCreate(host.platformWindow) },
            requestCloseWindow: { host in host.windowWillClose(host.platformWindow) },
            runMessageLoop: { 0 }, terminateMessageLoop: {}),
        hostFactory: { configuration, _ in driver.makeHost(configuration) },
        documentServices: .headless(files: OwnedRootNoFiles()))
}

private enum OwnedRootContentFailure: Error { case unexpectedFileOperation }

@MainActor
private final class OwnedRootNoFiles: DocumentFileService {
    func chooseOpenURL(types: [UTType], owner: FileDialogOwner) -> FileDialogOutcome<URL> { .cancelled }
    func chooseSaveURL(name: String?, directory: URL?, type: UTType, owner: FileDialogOwner) -> FileDialogOutcome<URL> {
        .cancelled
    }
    func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
        throw OwnedRootContentFailure.unexpectedFileOperation
    }
    func writeRegularFile(
        to url: URL, provideData: @MainActor (URL) throws -> Data, validate: @MainActor () throws -> Void
    ) throws -> Data { throw OwnedRootContentFailure.unexpectedFileOperation }
}

@MainActor
private func ownedRootNodes(_ root: ViewNode) -> [ViewNode] {
    MountedLazyListTestHost.descendants(in: root)
}

@MainActor
private func ownedRootButton(in runtime: RetainedViewRuntime) throws -> ViewNode {
    try XCTUnwrap(
        ownedRootNodes(runtime.root).first { $0.accessibilityIdentifier == "owned.root.0" && $0.onActivate != nil })
}
