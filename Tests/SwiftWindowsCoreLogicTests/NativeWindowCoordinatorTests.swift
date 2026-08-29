import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

private enum NativeCoordinatorTestFailure: Error, Equatable {
    case create
    case cleanup
}

private final class NativeCoordinatorReleaseProbe: Sendable {
    let onRelease: @Sendable () -> Void

    init(onRelease: @escaping @Sendable () -> Void) {
        self.onRelease = onRelease
    }

    deinit { onRelease() }
}

@MainActor
private final class NativeCoordinatorReleaseObservation {
    var probeInstallations = 0
    var releases = 0
    var windowCounts: [Int] = []
}

/// Every native operation below is a controlled continuation, never an HWND
/// or a message loop. These tests cover routing/lifetime semantics only.
@MainActor
private final class NativeCoordinatorTestDriver {
    var ownerStarts = 0
    var ownerStops = 0
    var activations = 0
    var closeRequests = 0
    var discards = 0
    var discardFailure: NativeCoordinatorTestFailure?
    var duringFactory: (@MainActor (WindowGroupConfiguration) -> Void)?
    var duringSettingsContent: (@MainActor () -> Void)?
    var duringValueContent: (@MainActor () -> Void)?
    var duringScope: (@MainActor (Int) -> Void)?
    var makeReleaseProbe: (@MainActor (WindowGroupConfiguration) -> NativeCoordinatorReleaseProbe?)?
    var factoryCalls = 0
    var scopeCalls = 0
    var starts: [WinSwiftUIWindowHost] = []
    private var unobservedStarts: [WinSwiftUIWindowHost] = []
    private var nextStart: CheckedContinuation<WinSwiftUIWindowHost, Never>?
    private var permits: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]
    private var stopPermit: CheckedContinuation<Int32, Never>?
    private var stopObserver: CheckedContinuation<Void, Never>?

    func hooks() -> WindowCoordinatorNativeHooks {
        WindowCoordinatorNativeHooks(
            startOwner: { self.ownerStarts += 1 },
            startWindow: { host in
                try await withCheckedThrowingContinuation { continuation in
                    self.permits[ObjectIdentifier(host)] = continuation
                    self.starts.append(host)
                    if let waiting = self.nextStart {
                        self.nextStart = nil
                        waiting.resume(returning: host)
                    } else {
                        self.unobservedStarts.append(host)
                    }
                }
                if !host.isClosed { host.windowDidCreate(host.platformWindow) }
            },
            activateWindow: { _ in
                self.activations += 1
                return false  // A real refusal is not a request to duplicate.
            },
            requestCloseWindow: { host in
                self.closeRequests += 1
                guard host.windowShouldClose(host.platformWindow) else { return }
                host.windowWillClose(host.platformWindow)
            },
            discardFailedWindow: { host in
                self.discards += 1
                if let failure = self.discardFailure { throw failure }
                host.windowWillClose(host.platformWindow)
            },
            stopOwner: {
                self.ownerStops += 1
                return await withCheckedContinuation { continuation in
                    self.stopPermit = continuation
                    let observer = self.stopObserver
                    self.stopObserver = nil
                    observer?.resume()
                }
            }
        )
    }

    func legacyHooks() -> WindowCoordinatorHooks {
        WindowCoordinatorHooks(
            startWindow: { host in
                self.starts.append(host)
                host.windowDidCreate(host.platformWindow)
            },
            requestCloseWindow: { host in
                guard host.windowShouldClose(host.platformWindow) else { return }
                host.windowWillClose(host.platformWindow)
            },
            runMessageLoop: { 0 },
            terminateMessageLoop: { self.ownerStops += 1 }
        )
    }

    func observeStart() async -> WinSwiftUIWindowHost {
        if !unobservedStarts.isEmpty { return unobservedStarts.removeFirst() }
        return await withCheckedContinuation { nextStart = $0 }
    }

    func completeStart(_ host: WinSwiftUIWindowHost, result: Result<Void, any Error> = .success(())) {
        let permit = permits.removeValue(forKey: ObjectIdentifier(host))
        XCTAssertNotNil(permit)
        permit?.resume(with: result)
    }

    func observeStop() async {
        if stopPermit != nil { return }
        await withCheckedContinuation { stopObserver = $0 }
    }

    func completeStop(_ exitCode: Int32 = 0) {
        let permit = stopPermit
        stopPermit = nil
        XCTAssertNotNil(permit)
        permit?.resume(returning: exitCode)
    }

    func forgetStartedHost(_ host: WinSwiftUIWindowHost) {
        XCTAssertNil(permits[ObjectIdentifier(host)])
        starts.removeAll { $0 === host }
        unobservedStarts.removeAll { $0 === host }
    }

    func clearCallbacks() {
        duringFactory = nil
        duringSettingsContent = nil
        duringValueContent = nil
        duringScope = nil
        makeReleaseProbe = nil
    }
}

@MainActor
final class NativeWindowCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        _ driver: NativeCoordinatorTestDriver, usesNativeOwner: Bool = true
    ) -> WinSwiftUIWindowCoordinator {
        var settings = WindowGroupConfiguration(
            title: "Settings", size: IntSize(width: 300, height: 200), clearColor: .black, content: []
        )
        settings.isSettingsWindow = true
        settings.windowContentFactory = {
            driver.duringSettingsContent?()
            return []
        }
        return WinSwiftUIWindowCoordinator(
            sceneConfigurations: [
                WindowGroupConfiguration(
                    title: "Primary", size: IntSize(width: 640, height: 480), clearColor: .black, content: [],
                    windowID: "main"
                ),
                settings,
                WindowGroupConfiguration(
                    title: "Value", size: IntSize(width: 300, height: 200), clearColor: .black, content: [],
                    windowID: "value", forType: String.self,
                    dataBoundContent: { _ in
                        driver.duringValueContent?()
                        return []
                    }
                ),
            ],
            hooks: usesNativeOwner ? nil : driver.legacyHooks(),
            nativeHooks: usesNativeOwner ? driver.hooks() : nil,
            hostFactory: { configuration, _ in
                driver.factoryCalls += 1
                driver.duringFactory?(configuration)
                let releaseProbe = driver.makeReleaseProbe?(configuration)
                return WinSwiftUIWindowHost(
                    configuration: configuration, renderer: FakeRenderBackend(), batchRenderer: nil,
                    surfaceDescriptorProvider: { [releaseProbe] _ in
                        withExtendedLifetime(releaseProbe) {}
                        return SurfaceDescriptor(offscreenPixelSize: IntSize(width: 640, height: 480))
                    },
                    startupProbeConfiguration: nil
                )
            },
            sceneStorageScopeProvider: {
                driver.scopeCalls += 1
                driver.duringScope?(driver.scopeCalls)
                return "native-test-\(driver.scopeCalls)"
            }
        )
    }

    private func closeAndRelinquish(
        _ value: inout WinSwiftUIWindowHost?, driver: NativeCoordinatorTestDriver
    ) {
        guard let closing = value else { return XCTFail("Expected an earlier live host.") }
        driver.forgetStartedHost(closing)
        value = nil
        closing.windowWillClose(closing.platformWindow)
    }

    func testNativeRunReturnsOnlyAfterStopAcknowledgement() async throws {
        let driver = NativeCoordinatorTestDriver()
        let coordinator = makeCoordinator(driver)
        var didReturn = false
        let run = Task { @MainActor in
            let result = try await coordinator.runNative()
            didReturn = true
            return result
        }
        let primary = await driver.observeStart()
        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(driver.ownerStarts, 1)
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
        await driver.observeStop()
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(driver.ownerStops, 1)
        XCTAssertFalse(didReturn)
        driver.completeStop(23)
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 23)
        XCTAssertTrue(didReturn)
    }

    func testPendingSettingsAreDeduplicatedAndDismissIsNotLost() async throws {
        let driver = NativeCoordinatorTestDriver()
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()

        let first = try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        let duplicate = try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        XCTAssertEqual(coordinator.windowCount, 2)
        let settings = await driver.observeStart()
        XCTAssertEqual(driver.starts.count, 2)
        coordinator.dismissWindow(payload: WindowActionPayload(), from: settings)
        XCTAssertEqual(driver.closeRequests, 0)
        driver.completeStart(settings)
        _ = try? await first.value
        _ = try? await duplicate.value
        XCTAssertEqual(driver.closeRequests, 1)
        XCTAssertEqual(driver.starts.count, 2)
        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(driver.ownerStops, 0)

        coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
        await driver.observeStop()
        driver.completeStop()
        _ = try await run.value
    }

    func testStartupFailurePreservesItsErrorAndWaitsForCleanupAndStop() async throws {
        let driver = NativeCoordinatorTestDriver()
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary, result: .failure(NativeCoordinatorTestFailure.create))
        await driver.observeStop()
        XCTAssertEqual(driver.discards, 1)
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(driver.ownerStops, 1)
        driver.completeStop()
        do {
            _ = try await run.value
            XCTFail("A failed creation must not become a successful owner exit.")
        } catch {
            XCTAssertEqual(error as? NativeCoordinatorTestFailure, .create)
        }
    }

    func testFailedCleanupRetainsWindowAndDoesNotDeclareNormalShutdown() async throws {
        let driver = NativeCoordinatorTestDriver()
        driver.discardFailure = .cleanup
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary, result: .failure(NativeCoordinatorTestFailure.create))
        do {
            _ = try await run.value
            XCTFail("Cleanup failure must remain visible.")
        } catch NativeWindowCoordinatorError.startupAndCleanup(let startup, let cleanup) {
            XCTAssertEqual(startup as? NativeCoordinatorTestFailure, .create)
            XCTAssertEqual(cleanup as? NativeCoordinatorTestFailure, .cleanup)
        }
        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(driver.ownerStops, 0)
        XCTAssertEqual(coordinator.nativeLifecycleFailures.count, 2)
        // Supply the otherwise missing terminal destruction receipt to drain
        // this headless fixture. No production failure is treated as a receipt.
        primary.windowWillClose(primary.platformWindow)
        await driver.observeStop()
        driver.completeStop()
    }

    func testFatalOwnerFailureReleasesRunWithoutInventingDestruction() async throws {
        let driver = NativeCoordinatorTestDriver()
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        let failure = NativeWindowOwnerFailure.postFailed(code: 42)
        primary.onNativeFailure?(primary, failure)
        do {
            _ = try await run.value
            XCTFail("A fatal owner failure must release the run's waiter with its error.")
        } catch {
            XCTAssertEqual(error as? NativeWindowOwnerFailure, failure)
        }
        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(driver.ownerStops, 0)
        XCTAssertEqual(driver.closeRequests, 0)
        XCTAssertFalse(primary.isClosed)
        primary.windowWillClose(primary.platformWindow)
        await driver.observeStop()
        driver.completeStop()
    }

    func testFatalFailureDuringStartupDoesNotDropTheAdmittedOperation() async throws {
        let driver = NativeCoordinatorTestDriver()
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        let failure = NativeWindowOwnerFailure.ownerStopped
        primary.onNativeFailure?(primary, failure)
        do {
            _ = try await run.value
            XCTFail("Startup must not wait forever after a fatal ownership error.")
        } catch {
            XCTAssertEqual(error as? NativeWindowOwnerFailure, failure)
        }
        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(driver.ownerStops, 0)
        // The real admitted operation still has its continuation and host.
        // Supplying its actual completion is distinct from the earlier error.
        driver.completeStart(primary)
        let completed = try await coordinator.bootPrimaryNativeWindow()
        XCTAssertTrue(completed === primary)
        primary.windowWillClose(primary.platformWindow)
        await driver.observeStop()
        driver.completeStop()
    }

    func testSynchronousEntryDoesNotRunAnAsynchronousOwner() async {
        let driver = NativeCoordinatorTestDriver()
        let coordinator = makeCoordinator(driver)
        XCTAssertThrowsError(try coordinator.run())
        XCTAssertThrowsError(try coordinator.bootPrimaryWindow())
        XCTAssertFalse(coordinator.openSettings())
        XCTAssertFalse(coordinator.openWindow(payload: WindowActionPayload(id: "main")))
        XCTAssertEqual(driver.ownerStarts, 0)
        XCTAssertTrue(driver.starts.isEmpty)
    }

    func testObservedOrdinaryCloseDuringStartupKeepsNormalExitDistinctFromFailure() async throws {
        let driver = NativeCoordinatorTestDriver()
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        // A real native close acknowledgement can precede the activation or
        // first-frame reply. This fixture supplies those events independently.
        primary.windowWillClose(primary.platformWindow)
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(driver.ownerStops, 0)
        driver.completeStart(primary)
        await driver.observeStop()
        XCTAssertEqual(driver.discards, 0)
        XCTAssertTrue(coordinator.nativeLifecycleFailures.isEmpty)
        driver.completeStop()
        let result = try await run.value
        XCTAssertEqual(result, 0)
    }

    func testLastCloseReservesAdmissionBeforeReleasingAnEarlierHost() async throws {
        let driver = NativeCoordinatorTestDriver()
        defer { driver.clearCallbacks() }
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        let reopen = try XCTUnwrap(primary.windowEnvironment).openSettings
        let observation = NativeCoordinatorReleaseObservation()
        driver.makeReleaseProbe = { configuration in
            guard configuration.isSettingsWindow, observation.probeInstallations == 0 else { return nil }
            observation.probeInstallations += 1
            return NativeCoordinatorReleaseProbe {
                // The fixture requires synchronous destruction on this actor;
                // this assertion does not enqueue or move the release callback.
                MainActor.assumeIsolated {
                    observation.releases += 1
                    observation.windowCounts.append(coordinator.windowCount)
                    reopen()
                    observation.windowCounts.append(coordinator.windowCount)
                }
            }
        }
        var settingsStart: Task<WinSwiftUIWindowHost, any Error>? =
            try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        var earlier: WinSwiftUIWindowHost? = await driver.observeStart()
        driver.completeStart(try XCTUnwrap(earlier))
        _ = try await settingsStart?.value
        settingsStart = nil  // A completed Task result must not retain the host.
        weak var releasedHost = earlier

        // Neither close below suspends. The queued release task cannot run
        // between them, and the driver/local no longer own the earlier host.
        closeAndRelinquish(&earlier, driver: driver)
        XCTAssertNotNil(releasedHost)
        XCTAssertEqual(observation.releases, 0)
        primary.windowWillClose(primary.platformWindow)

        XCTAssertNil(releasedHost)
        XCTAssertEqual(observation.releases, 1)
        XCTAssertEqual(observation.windowCounts, [0, 0])
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(driver.factoryCalls, 2)
        XCTAssertEqual(driver.starts.count, 1)

        // Keep a failed assertion from leaving a newly admitted fake start
        // suspended forever. The passing path has no windows to clean up.
        for managed in coordinator.windows {
            let unexpected = await driver.observeStart()
            XCTAssertTrue(unexpected === managed.host)
            driver.completeStart(unexpected)
            unexpected.windowWillClose(unexpected.platformWindow)
        }
        await driver.observeStop()
        XCTAssertEqual(driver.ownerStops, 1)
        driver.completeStop()
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 0)
    }

    func testLegacyReleaseMayReopenBeforeTheActualLastWindowQuitCheck() async throws {
        let driver = NativeCoordinatorTestDriver()
        defer { driver.clearCallbacks() }
        let coordinator = makeCoordinator(driver, usesNativeOwner: false)
        let primary = try coordinator.bootPrimaryWindow()
        let reopen = try XCTUnwrap(primary.windowEnvironment).openSettings
        let observation = NativeCoordinatorReleaseObservation()
        driver.makeReleaseProbe = { configuration in
            guard configuration.isSettingsWindow, observation.probeInstallations == 0 else { return nil }
            observation.probeInstallations += 1
            return NativeCoordinatorReleaseProbe {
                MainActor.assumeIsolated {
                    observation.releases += 1
                    observation.windowCounts.append(coordinator.windowCount)
                    reopen()
                    observation.windowCounts.append(coordinator.windowCount)
                }
            }
        }
        XCTAssertTrue(coordinator.openSettings())
        var earlier = coordinator.windows.first(where: { $0.configuration.isSettingsWindow })?.host
        weak var releasedHost = earlier
        closeAndRelinquish(&earlier, driver: driver)
        XCTAssertNotNil(releasedHost)
        XCTAssertEqual(observation.releases, 0)

        // The legacy callback retains its established synchronous behavior:
        // release of the old Settings host may open another one before the
        // current primary is removed. Quit must inspect the resulting list.
        primary.windowWillClose(primary.platformWindow)
        XCTAssertNil(releasedHost)
        XCTAssertEqual(observation.releases, 1)
        XCTAssertEqual(observation.windowCounts, [1, 2])
        XCTAssertEqual(driver.factoryCalls, 3)
        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(driver.ownerStops, 0)

        let replacement = try XCTUnwrap(coordinator.windows.first?.host)
        replacement.windowWillClose(replacement.platformWindow)
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(driver.ownerStops, 1)
    }

    func testAuthoredContentCannotOpenAfterClosingTheLastWindow() async throws {
        let driver = NativeCoordinatorTestDriver()
        defer { driver.clearCallbacks() }
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        driver.duringSettingsContent = {
            coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
        }
        XCTAssertThrowsError(try coordinator.beginNativeSettingsRequest()) { error in
            XCTAssertEqual(error as? WindowCoordinatorError, .coordinatorTerminated)
        }
        XCTAssertEqual(driver.factoryCalls, 1)
        XCTAssertEqual(driver.discards, 0)
        XCTAssertEqual(coordinator.windowCount, 0)
        await driver.observeStop()
        driver.completeStop()
        _ = try await run.value
    }

    func testFactoryClosingLastWindowRollsBackReturnedUnadmittedHost() async throws {
        let driver = NativeCoordinatorTestDriver()
        defer { driver.clearCallbacks() }
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        driver.duringFactory = { configuration in
            if configuration.isSettingsWindow {
                coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
                XCTAssertEqual(driver.ownerStops, 0)
            }
        }
        let rejected = try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        do {
            _ = try await rejected.value
            XCTFail("A factory callout cannot reopen admission after the last close.")
        } catch {
            XCTAssertEqual(error as? WindowCoordinatorError, .coordinatorTerminated)
        }
        XCTAssertEqual(driver.discards, 1)
        XCTAssertEqual(driver.starts.count, 1)
        XCTAssertEqual(coordinator.failedUnadmittedNativeHostCount, 0)
        await driver.observeStop()
        driver.completeStop()
        _ = try await run.value
    }

    func testScopeProviderClosingLastWindowAlsoRollsBackBeforeStartup() async throws {
        let driver = NativeCoordinatorTestDriver()
        defer { driver.clearCallbacks() }
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        driver.duringScope = { call in
            if call == 2 { coordinator.dismissWindow(payload: WindowActionPayload(), from: primary) }
        }
        let rejected = try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        do {
            _ = try await rejected.value
            XCTFail("Scope-provider reentry must be validated before actor admission.")
        } catch {
            XCTAssertEqual(error as? WindowCoordinatorError, .coordinatorTerminated)
        }
        XCTAssertEqual(driver.discards, 1)
        XCTAssertEqual(driver.starts.count, 1)
        await driver.observeStop()
        driver.completeStop()
        _ = try await run.value
    }

    func testFactoryAndValueReentryCannotCreateDuplicatePreparations() async throws {
        let driver = NativeCoordinatorTestDriver()
        defer { driver.clearCallbacks() }
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        var rejectedReentries = 0
        driver.duringFactory = { configuration in
            if configuration.isSettingsWindow {
                do {
                    _ = try coordinator.beginNativeSettingsRequest()
                    XCTFail("A recursive factory must not start another Settings host.")
                } catch NativeWindowCoordinatorError.reentrantWindowPreparation {
                    rejectedReentries += 1
                } catch { XCTFail("Unexpected reentry error: \(error)") }
            }
        }
        let settingsTask = try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        let settings = await driver.observeStart()
        driver.completeStart(settings)
        _ = try await settingsTask.value
        let valuePayload = WindowActionPayload(id: "value", value: AnyHashable("same"))
        driver.duringValueContent = {
            do {
                _ = try coordinator.beginNativeWindowRequest(payload: valuePayload)
                XCTFail("Data-bound content must run inside the preparation reservation.")
            } catch NativeWindowCoordinatorError.reentrantWindowPreparation {
                rejectedReentries += 1
            } catch { XCTFail("Unexpected reentry error: \(error)") }
        }
        let valueTask = try XCTUnwrap(coordinator.beginNativeWindowRequest(payload: valuePayload))
        let valueHost = await driver.observeStart()
        driver.completeStart(valueHost)
        _ = try await valueTask.value
        XCTAssertEqual(rejectedReentries, 2)
        XCTAssertEqual(coordinator.windowCount, 3)
        XCTAssertEqual(driver.starts.count, 3)
        coordinator.dismissWindow(payload: WindowActionPayload(), from: settings)
        coordinator.dismissWindow(payload: WindowActionPayload(), from: valueHost)
        coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
        await driver.observeStop()
        driver.completeStop()
        _ = try await run.value
    }

    func testDeclinedActivationHasSeparateActualOutcomeFromSceneRouting() async throws {
        let driver = NativeCoordinatorTestDriver()
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        let first = try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        let settings = await driver.observeStart()
        driver.completeStart(settings)
        _ = try await first.value
        let found = try await coordinator.openNativeSettings()
        XCTAssertTrue(found)
        XCTAssertEqual(coordinator.lastNativeActivationResult(for: settings), false)
        XCTAssertEqual(driver.activations, 1)
        XCTAssertEqual(driver.starts.count, 2)
        coordinator.dismissWindow(payload: WindowActionPayload(), from: settings)
        coordinator.dismissWindow(payload: WindowActionPayload(), from: primary)
        await driver.observeStop()
        driver.completeStop()
        _ = try await run.value
    }

    func testFailedUnadmittedCleanupRetainsHostAndFailsTheRun() async throws {
        let driver = NativeCoordinatorTestDriver()
        defer { driver.clearCallbacks() }
        let coordinator = makeCoordinator(driver)
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        driver.completeStart(primary)
        _ = try await coordinator.bootPrimaryNativeWindow()
        driver.discardFailure = .cleanup
        driver.duringScope = { call in
            if call == 2 { coordinator.dismissWindow(payload: WindowActionPayload(), from: primary) }
        }
        let rejected = try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        do {
            _ = try await rejected.value
            XCTFail("A failed unadmitted cleanup must retain its error and ownership.")
        } catch NativeWindowCoordinatorError.startupAndCleanup(let startup, let cleanup) {
            XCTAssertEqual(startup as? WindowCoordinatorError, .coordinatorTerminated)
            XCTAssertEqual(cleanup as? NativeCoordinatorTestFailure, .cleanup)
        }
        do {
            _ = try await run.value
            XCTFail("Normal owner stop is forbidden while failed resources remain.")
        } catch NativeWindowCoordinatorError.startupAndCleanup(_, let cleanup) {
            XCTAssertEqual(cleanup as? NativeCoordinatorTestFailure, .cleanup)
        }
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(coordinator.failedUnadmittedNativeHostCount, 1)
        XCTAssertEqual(driver.ownerStops, 0)
        XCTAssertEqual(driver.starts.count, 1)
    }
}
