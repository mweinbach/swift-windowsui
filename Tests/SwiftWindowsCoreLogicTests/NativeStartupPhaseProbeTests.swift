import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

@MainActor
private final class StartupPhaseAudit {
    var records: [[UInt8]] = []
    var events: [String] = []
    var succeeds = true
    var duringWrite: (() -> Void)?

    var text: [String] { records.map { String(decoding: $0, as: UTF8.self) } }

    func sink() -> NativeStartupPhaseProbe.Sink {
        { [self] bytes in
            records.append(bytes)
            events.append(String(decoding: bytes, as: UTF8.self))
            duringWrite?()
            return succeeds
        }
    }
}

private enum StartupPhaseTestFailure: Error, Equatable {
    case owner
    case window
}

/// These hooks suspend only on test-owned continuations. They never start an
/// OS thread, create an HWND, or call a renderer's native API.
@MainActor
private final class StartupPhaseCoordinatorDriver {
    let audit: StartupPhaseAudit
    var holdsOwner = false
    var ownerFailure: StartupPhaseTestFailure?
    var ownerStops = 0
    var discardedWindows = 0
    private var ownerEntered = false
    private var ownerObserver: CheckedContinuation<Void, Never>?
    private var ownerPermit: CheckedContinuation<Void, Never>?
    private var starts: [WinSwiftUIWindowHost] = []
    private var startObserver: CheckedContinuation<WinSwiftUIWindowHost, Never>?
    private var startPermits: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]

    init(audit: StartupPhaseAudit) { self.audit = audit }

    func hooks() -> WindowCoordinatorNativeHooks {
        WindowCoordinatorNativeHooks(
            startOwner: {
                self.audit.events.append("owner.entered")
                self.ownerEntered = true
                let observer = self.ownerObserver
                self.ownerObserver = nil
                observer?.resume()
                if let failure = self.ownerFailure { throw failure }
                if self.holdsOwner {
                    await withCheckedContinuation { self.ownerPermit = $0 }
                }
                self.audit.events.append("owner.returned")
            },
            startWindow: { host, _ in
                self.audit.events.append("window.entered")
                try await withCheckedThrowingContinuation { continuation in
                    self.startPermits[ObjectIdentifier(host)] = continuation
                    if let observer = self.startObserver {
                        self.startObserver = nil
                        observer.resume(returning: host)
                    } else {
                        self.starts.append(host)
                    }
                }
                if !host.isClosed { host.windowDidCreate(host.platformWindow) }
                self.audit.events.append("window.returned")
            },
            activateWindow: { _ in false },
            requestCloseWindow: { host in
                guard host.windowShouldClose(host.platformWindow) else { return }
                host.windowWillClose(host.platformWindow)
            },
            discardFailedWindow: { host in
                self.discardedWindows += 1
                host.windowWillClose(host.platformWindow)
            },
            stopOwner: {
                self.ownerStops += 1
                self.audit.events.append("owner.stopped")
                return 0
            }
        )
    }

    func observeOwner() async {
        if ownerEntered { return }
        await withCheckedContinuation { ownerObserver = $0 }
    }

    func releaseOwner() {
        guard let permit = ownerPermit else { return XCTFail("Expected a held owner start.") }
        ownerPermit = nil
        permit.resume()
    }

    func observeStart() async -> WinSwiftUIWindowHost {
        if !starts.isEmpty { return starts.removeFirst() }
        return await withCheckedContinuation { startObserver = $0 }
    }

    func releaseStart(
        _ host: WinSwiftUIWindowHost, result: Result<Void, any Error> = .success(())
    ) {
        guard let permit = startPermits.removeValue(forKey: ObjectIdentifier(host)) else {
            return XCTFail("Expected an original pending window start.")
        }
        permit.resume(with: result)
    }
}

@MainActor
final class NativeStartupPhaseProbeTests: XCTestCase {
    private let validArguments = ["app", "--native-display-journal", #"C:\owned\journal.json"#]

    private func probe(_ audit: StartupPhaseAudit) throws -> NativeStartupPhaseProbe {
        try XCTUnwrap(
            NativeStartupPhaseProbe.makeIfRequested(arguments: validArguments, makeSink: { audit.sink() }))
    }

    private func host(_ title: String = "Startup phase fixture") -> WinSwiftUIWindowHost {
        WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: title, size: IntSize(width: 8, height: 8), clearColor: .black, content: []),
            renderer: FakeRenderBackend(),
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in
                SurfaceDescriptor(offscreenPixelSize: IntSize(width: 8, height: 8))
            },
            startupProbeConfiguration: nil)
    }

    private func coordinator(
        _ driver: StartupPhaseCoordinatorDriver, probe: NativeStartupPhaseProbe? = nil
    ) -> WinSwiftUIWindowCoordinator {
        var settings = WindowGroupConfiguration(
            title: "Settings", size: IntSize(width: 8, height: 8), clearColor: .black, content: [])
        settings.isSettingsWindow = true
        return WinSwiftUIWindowCoordinator(
            sceneConfigurations: [
                WindowGroupConfiguration(
                    title: "Primary", size: IntSize(width: 8, height: 8), clearColor: .black, content: []),
                settings,
            ],
            nativeHooks: driver.hooks(),
            hostFactory: { configuration, _ in
                driver.audit.events.append("host.created")
                return WinSwiftUIWindowHost(
                    configuration: configuration, renderer: FakeRenderBackend(), batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in
                        SurfaceDescriptor(offscreenPixelSize: IntSize(width: 8, height: 8))
                    },
                    startupProbeConfiguration: nil)
            },
            sceneStorageScopeProvider: { "startup-phase-test" },
            nativeStartupPhaseProbe: probe)
    }

    func testAbsentFlagDoesNotObtainSink() async {
        var obtained = 0
        for arguments in [[], ["app"], ["app", "--diagnostics", "--diagnostics-no-input"]] {
            let value = NativeStartupPhaseProbe.makeIfRequested(
                arguments: arguments,
                makeSink: {
                    obtained += 1
                    return { _ in true }
                })
            XCTAssertNil(value)
        }
        XCTAssertEqual(obtained, 0)
    }

    func testMalformedArgumentsDoNotObtainSink() async {
        let malformed = [
            ["app", "--native-display-journal"],
            ["app", "--native-display-journal=" + #"C:\owned\journal.json"#],
            validArguments + ["--native-display-journal", #"D:\second.json"#],
            validArguments + ["--native-display-journal=ignored"],
        ]
        var obtained = 0
        for arguments in malformed {
            XCTAssertNil(
                NativeStartupPhaseProbe.makeIfRequested(
                    arguments: arguments,
                    makeSink: {
                        obtained += 1
                        return { _ in true }
                    }))
        }
        XCTAssertEqual(obtained, 0)
    }

    func testInvalidPathsDoNotObtainSink() async {
        let paths = [
            "journal.json", #"C:journal.json"#, #"\\server\share\journal.json"#,
            #"\\?\C:\journal.json"#, #"C:\owned\..\journal.json"#, #"C:\owned\NUL.json"#,
            #"C:\owned\COM1.txt"#, "C:\\owned\\journal.json ", "C:\\owned\\",
            "C:\\owned\\bad\u{0}name.json", "C:\\" + String(repeating: "a", count: 3998),
        ]
        var obtained = 0
        for path in paths {
            XCTAssertNil(
                NativeStartupPhaseProbe.makeIfRequested(
                    arguments: ["app", "--native-display-journal", path],
                    makeSink: {
                        obtained += 1
                        return { _ in true }
                    }),
                path)
        }
        XCTAssertEqual(obtained, 0)
    }

    func testGateUsesExistingParserRatherThanNewPathOrDiagnosticsRules() async throws {
        let paths = [
            #"C:\owned\journal.json"#, "d:/owned output/journal.json", "C:\\" + String(repeating: "a", count: 3997),
        ]
        var obtained = 0
        for path in paths {
            let arguments = [
                "app", "--diagnostics", "--diagnostics-seconds", "0.5", "--diagnostics-no-input",
                "--diagnostics-output", #"C:\owned\diagnostics.json"#, "--native-display-journal", path,
            ]
            XCTAssertNotNil(try NativeDisplayAcquisitionConfiguration.parse(arguments: arguments))
            let value = NativeStartupPhaseProbe.makeIfRequested(
                arguments: arguments,
                makeSink: {
                    obtained += 1
                    return { _ in true }
                })
            XCTAssertNotNil(value)
        }
        XCTAssertEqual(obtained, paths.count)
    }

    func testUnavailableSinkDoesNotProduceProbeOrThrow() async {
        var obtained = 0
        XCTAssertNil(
            NativeStartupPhaseProbe.makeIfRequested(
                arguments: validArguments,
                makeSink: {
                    obtained += 1
                    return nil
                }))
        XCTAssertEqual(obtained, 1)
    }

    func testConstructionDoesNotEmitAnUnreachedPhase() async throws {
        let audit = StartupPhaseAudit()
        let value = try probe(audit)
        XCTAssertTrue(audit.records.isEmpty)
        withExtendedLifetime(value) {}
    }

    func testNineFixedRecordsHaveExactScalarVocabularyAndBound() async throws {
        let audit = StartupPhaseAudit()
        let value = try probe(audit)
        XCTAssertEqual(NativeStartupPhaseProbe.Phase.allCases.map(\.rawValue), Array(UInt8(1)...UInt8(9)))
        for phase in NativeStartupPhaseProbe.Phase.allCases { value.record(phase) }
        XCTAssertEqual(audit.text, (1...9).map { "SWUI_STARTUP_PHASE \($0)\n" })
        XCTAssertEqual(audit.records.map(\.count), Array(repeating: 21, count: 9))
        XCTAssertEqual(audit.records.reduce(0) { $0 + $1.count }, 189)
    }

    func testMarkerBytesDoNotContainConfigurationOrOtherArguments() async throws {
        let first = StartupPhaseAudit()
        let second = StartupPhaseAudit()
        let firstProbe = try probe(first)
        let secondProbe = try XCTUnwrap(
            NativeStartupPhaseProbe.makeIfRequested(
                arguments: [
                    "private-user-data", "--native-display-journal", #"Z:\private-user-data\secret.json"#,
                    "--unrelated-private-data",
                ],
                makeSink: { second.sink() }))
        for phase in NativeStartupPhaseProbe.Phase.allCases {
            firstProbe.record(phase)
            secondProbe.record(phase)
        }
        XCTAssertEqual(first.records, second.records)
        XCTAssertFalse(second.text.joined().contains("private"))
        XCTAssertFalse(second.text.joined().contains("secret"))
    }

    func testRepeatedAndEarlierPhasesAreNotWrittenAgain() async throws {
        let audit = StartupPhaseAudit()
        let value = try probe(audit)
        value.record(.mainEntered)
        value.record(.mainEntered)
        value.record(.backendResolved)
        value.record(.applicationInitialized)
        value.record(.backendResolved)
        XCTAssertEqual(audit.text, ["SWUI_STARTUP_PHASE 1\n", "SWUI_STARTUP_PHASE 3\n"])
    }

    func testMissingPhasesDoNotSuppressTruthfulLaterBoundary() async throws {
        let audit = StartupPhaseAudit()
        let value = try probe(audit)
        value.record(.nativeTaskEntered)
        value.record(.nativeRunReturned)
        value.record(.retirementReturned)
        XCTAssertEqual(
            audit.text, ["SWUI_STARTUP_PHASE 4\n", "SWUI_STARTUP_PHASE 8\n", "SWUI_STARTUP_PHASE 9\n"])
    }

    func testFailedWriteDisablesAllLaterAttempts() async throws {
        let audit = StartupPhaseAudit()
        audit.succeeds = false
        let value = try probe(audit)
        value.record(.mainEntered)
        audit.succeeds = true
        for phase in NativeStartupPhaseProbe.Phase.allCases { value.record(phase) }
        XCTAssertEqual(audit.text, ["SWUI_STARTUP_PHASE 1\n"])
    }

    func testWriteResultRequiresSuccessfulFullByteCount() async {
        XCTAssertTrue(NativeStartupPhaseProbe.isCompleteWrite(succeeded: true, written: 21, expected: 21))
        XCTAssertFalse(NativeStartupPhaseProbe.isCompleteWrite(succeeded: false, written: 21, expected: 21))
        XCTAssertFalse(NativeStartupPhaseProbe.isCompleteWrite(succeeded: true, written: 0, expected: 21))
        XCTAssertFalse(NativeStartupPhaseProbe.isCompleteWrite(succeeded: true, written: 20, expected: 21))
        XCTAssertFalse(NativeStartupPhaseProbe.isCompleteWrite(succeeded: true, written: 22, expected: 21))
        XCTAssertFalse(NativeStartupPhaseProbe.isCompleteWrite(succeeded: true, written: .max, expected: 21))
    }

    func testShortWriteDisablesProbeWithoutCompletingOrRetryingRecord() async throws {
        var attempts: [[UInt8]] = []
        let value = try XCTUnwrap(
            NativeStartupPhaseProbe.makeIfRequested(
                arguments: validArguments,
                makeSink: {
                    { bytes in
                        attempts.append(bytes)
                        return NativeStartupPhaseProbe.isCompleteWrite(
                            succeeded: true, written: 20, expected: UInt32(bytes.count))
                    }
                }))
        for phase in NativeStartupPhaseProbe.Phase.allCases { value.record(phase) }
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.count, 21)
    }

    func testReentrantSinkCannotEmitOrConsumeAnotherPhase() async throws {
        let audit = StartupPhaseAudit()
        let value = try probe(audit)
        weak var borrowed = value
        audit.duringWrite = {
            borrowed?.record(.mainEntered)
            borrowed?.record(.applicationInitialized)
        }
        value.record(.mainEntered)
        audit.duringWrite = nil
        value.record(.applicationInitialized)
        XCTAssertEqual(audit.text, ["SWUI_STARTUP_PHASE 1\n", "SWUI_STARTUP_PHASE 2\n"])
    }

    func testFailureReleasesSinkCapture() async throws {
        weak var borrowed: StartupPhaseAudit?
        let value: NativeStartupPhaseProbe
        do {
            let audit = StartupPhaseAudit()
            audit.succeeds = false
            borrowed = audit
            value = try probe(audit)
        }
        XCTAssertNotNil(borrowed)
        value.record(.mainEntered)
        XCTAssertNil(borrowed)
    }

    func testFinalBoundaryReleasesSinkAndCannotRearm() async throws {
        weak var borrowed: StartupPhaseAudit?
        let value: NativeStartupPhaseProbe
        do {
            let audit = StartupPhaseAudit()
            borrowed = audit
            value = try probe(audit)
        }
        value.record(.retirementReturned)
        XCTAssertNil(borrowed)
        for phase in NativeStartupPhaseProbe.Phase.allCases { value.record(phase) }
        XCTAssertNil(borrowed)
    }

    func testIndependentProbeInstancesHaveIndependentBudgets() async throws {
        let first = StartupPhaseAudit()
        let second = StartupPhaseAudit()
        let a = try probe(first)
        let b = try probe(second)
        a.record(.retirementReturned)
        b.record(.mainEntered)
        XCTAssertEqual(first.text, ["SWUI_STARTUP_PHASE 9\n"])
        XCTAssertEqual(second.text, ["SWUI_STARTUP_PHASE 1\n"])
    }

    func testCoordinatorMarksOwnerOnlyAfterOriginalAcknowledgement() async throws {
        let audit = StartupPhaseAudit()
        let driver = StartupPhaseCoordinatorDriver(audit: audit)
        driver.holdsOwner = true
        let value = try probe(audit)
        let coordinator = coordinator(driver, probe: value)
        let run = Task { @MainActor in try await coordinator.runNative() }
        await driver.observeOwner()
        XCTAssertTrue(audit.records.isEmpty)
        XCTAssertEqual(audit.events, ["owner.entered"])
        driver.releaseOwner()
        let primary = await driver.observeStart()
        XCTAssertEqual(audit.text, ["SWUI_STARTUP_PHASE 5\n"])
        XCTAssertEqual(
            Array(audit.events.prefix(4)),
            ["owner.entered", "owner.returned", "SWUI_STARTUP_PHASE 5\n", "host.created"])
        driver.releaseStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        XCTAssertEqual(audit.text, ["SWUI_STARTUP_PHASE 5\n", "SWUI_STARTUP_PHASE 6\n"])
        coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(driver.ownerStops, 1)
    }

    func testOwnerThrowCannotClaimOwnerOrPrimaryReturn() async throws {
        let audit = StartupPhaseAudit()
        let driver = StartupPhaseCoordinatorDriver(audit: audit)
        driver.ownerFailure = .owner
        let coordinator = coordinator(driver, probe: try probe(audit))
        do {
            _ = try await coordinator.runNative()
            XCTFail("The original owner error must escape.")
        } catch {
            XCTAssertEqual(error as? StartupPhaseTestFailure, .owner)
        }
        XCTAssertTrue(audit.records.isEmpty)
        XCTAssertEqual(audit.events, ["owner.entered"])
        XCTAssertEqual(driver.ownerStops, 0)
    }

    func testWindowThrowCannotClaimPrimaryReturnAndKeepsCleanup() async throws {
        let audit = StartupPhaseAudit()
        let driver = StartupPhaseCoordinatorDriver(audit: audit)
        let coordinator = coordinator(driver, probe: try probe(audit))
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.releaseStart(primary, result: .failure(StartupPhaseTestFailure.window))
        do {
            _ = try await run.value
            XCTFail("The original window error must escape.")
        } catch {
            XCTAssertEqual(error as? StartupPhaseTestFailure, .window)
        }
        XCTAssertEqual(audit.text, ["SWUI_STARTUP_PHASE 5\n"])
        XCTAssertEqual(driver.discardedWindows, 1)
        XCTAssertEqual(driver.ownerStops, 1)
    }

    func testSecondaryReturnBeforePrimaryDoesNotClaimPrimaryPhase() async throws {
        let audit = StartupPhaseAudit()
        let driver = StartupPhaseCoordinatorDriver(audit: audit)
        let coordinator = coordinator(driver, probe: try probe(audit))
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        guard let settingsTask = try coordinator.beginNativeSettingsRequest() else {
            driver.releaseStart(primary)
            _ = try await coordinator.bootPrimaryNativeWindow()
            coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
            _ = try await run.value
            return XCTFail("Expected the original Settings request.")
        }
        let settings = await driver.observeStart()
        driver.releaseStart(settings)
        _ = try await settingsTask.value
        XCTAssertEqual(audit.text, ["SWUI_STARTUP_PHASE 5\n"])
        driver.releaseStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        XCTAssertEqual(audit.text, ["SWUI_STARTUP_PHASE 5\n", "SWUI_STARTUP_PHASE 6\n"])
        coordinator.dismissWindow(payload: WindowActionPayload(), from: settings)
        coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(driver.ownerStops, 1)
    }

    func testDefaultNilCoordinatorDoesNotChangeStartupOrCleanup() async throws {
        let audit = StartupPhaseAudit()
        let driver = StartupPhaseCoordinatorDriver(audit: audit)
        let coordinator = coordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.releaseStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(audit.records.isEmpty)
        XCTAssertEqual(
            audit.events,
            ["owner.entered", "owner.returned", "host.created", "window.entered", "window.returned", "owner.stopped"])
    }

    func testDiagnosticsMarkerOccursInsideBeginBeforeExistingClockAndReport() async throws {
        let audit = StartupPhaseAudit()
        let host = host()
        var receivedReport = false
        var reportWaiter: CheckedContinuation<Void, Never>?
        let session = LiveDiagnosticsSession(
            configuration: LiveDiagnosticsConfiguration(
                durationSeconds: 0.5, outputPath: "not-written.json", exercisesInput: false),
            host: host,
            clock: {
                audit.events.append("diagnostics.clock")
                return 0
            },
            requestClose: { XCTFail("This test does not finish diagnostics.") },
            nativeCommands: LiveDiagnosticsNativeCommands(
                setVSync: { _, _ in
                    XCTFail("The unchanged no-option startup must not configure vsync.")
                    return false
                },
                setGPUFrameTimingEnabled: { _, _ in
                    XCTFail("The unchanged no-option startup must not configure GPU timing.")
                    return false
                },
                setFrameCaptureEnabled: { _, _ in
                    XCTFail("The unchanged no-option startup must not configure capture.")
                    return false
                },
                poll: { _ in
                    XCTFail("Starting this fixture must not poll a native presenter.")
                    return false
                },
                waitForTeardown: { _ in
                    XCTFail("Starting this fixture must not wait for native teardown.")
                    return false
                }),
            nativeStartupPhaseProbe: try probe(audit),
            report: { _ in
                audit.events.append("diagnostics.report")
                receivedReport = true
                let waiter = reportWaiter
                reportWaiter = nil
                waiter?.resume()
            })
        XCTAssertTrue(audit.events.isEmpty)
        session.start()
        session.start()
        if !receivedReport {
            await withCheckedContinuation { reportWaiter = $0 }
        }
        XCTAssertEqual(
            audit.events, ["SWUI_STARTUP_PHASE 7\n", "diagnostics.clock", "diagnostics.report"])
        XCTAssertNotNil(host.onFramePresented)
        XCTAssertNil(host.platformWindow.nativeHandle)
        withExtendedLifetime(session) {}
    }

    func testLegacyDiagnosticsPreservesExistingClockBeforeBeginMarker() async throws {
        let audit = StartupPhaseAudit()
        let host = host()
        let session = LiveDiagnosticsSession(
            configuration: LiveDiagnosticsConfiguration(
                durationSeconds: 0.5, outputPath: "not-written.json", exercisesInput: false),
            host: host,
            clock: {
                audit.events.append("diagnostics.clock")
                return 0
            },
            requestClose: { XCTFail("This test does not finish diagnostics.") },
            nativeStartupPhaseProbe: try probe(audit),
            report: { _ in audit.events.append("diagnostics.report") })
        XCTAssertTrue(audit.events.isEmpty)
        session.start()
        session.start()
        XCTAssertEqual(
            audit.events, ["diagnostics.clock", "SWUI_STARTUP_PHASE 7\n", "diagnostics.report"])
        XCTAssertNotNil(host.onFramePresented)
        XCTAssertNil(host.platformWindow.nativeHandle)
        withExtendedLifetime(session) {}
    }

    func testDefaultNilDiagnosticsDoesNotObtainOrWriteMarkers() async {
        let audit = StartupPhaseAudit()
        let host = host()
        let session = LiveDiagnosticsSession(
            configuration: LiveDiagnosticsConfiguration(
                durationSeconds: 0.5, outputPath: "not-written.json", exercisesInput: false),
            host: host,
            clock: {
                audit.events.append("diagnostics.clock")
                return 0
            },
            requestClose: { XCTFail("This test does not finish diagnostics.") },
            report: { _ in audit.events.append("diagnostics.report") })
        session.start()
        XCTAssertTrue(audit.records.isEmpty)
        XCTAssertEqual(audit.events, ["diagnostics.clock", "diagnostics.report"])
        XCTAssertNil(host.platformWindow.nativeHandle)
        withExtendedLifetime(session) {}
    }
}
