import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

private enum AppFailureTestError: Error {
    case startup
    case cleanup
}

@MainActor
private final class AppFailureTestDriver {
    var failures: [AppFailure] = []
    var startOwnerFails = false
    var discardFails = false
    var stopFails = false
    var stops = 0
    var discards = 0
    var host: WinSwiftUIWindowHost?
    var beforeStopReturns: (@MainActor () async -> Void)?
    var afterStopReturns: (@MainActor () -> Void)?

    func coordinator() -> WinSwiftUIWindowCoordinator {
        WinSwiftUIWindowCoordinator(
            sceneConfigurations: [
                WindowGroupConfiguration(
                    title: "Independent app", size: IntSize(width: 320, height: 200),
                    clearColor: .black, content: [], windowID: "dashboard")
            ],
            nativeHooks: WindowCoordinatorNativeHooks(
                startOwner: {
                    if self.startOwnerFails { throw AppFailureTestError.startup }
                },
                startWindow: { host, _ in
                    self.host = host
                    throw AppFailureTestError.startup
                },
                activateWindow: { _ in false },
                requestCloseWindow: { host in host.windowWillClose(host.platformWindow) },
                discardFailedWindow: { host in
                    self.discards += 1
                    if self.discardFails { throw AppFailureTestError.cleanup }
                    host.windowWillClose(host.platformWindow)
                },
                stopOwner: {
                    defer {
                        if let completed = self.afterStopReturns {
                            // The coordinator publishes its join immediately
                            // after this hook returns, before the next actor turn.
                            Task { @MainActor in completed() }
                        }
                    }
                    self.stops += 1
                    await self.beforeStopReturns?()
                    if self.stopFails { throw AppFailureTestError.cleanup }
                    return 0
                }),
            hostFactory: { configuration, _ in
                WinSwiftUIWindowHost(
                    configuration: configuration, renderer: FakeRenderBackend(), batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in nil }, startupProbeConfiguration: nil)
            },
            appFailureHandler: { self.failures.append($0) })
    }
}

@MainActor
final class AppFailureReportingTests: XCTestCase {
    private func exhaustPresenter(
        _ host: WinSwiftUIWindowHost, clock: FakeRecoveryClock
    ) {
        host.windowDidCreate(host.platformWindow)
        for _ in 0..<12 {
            clock.now += 30
            host.windowNeedsDisplay(host.platformWindow)
        }
        XCTAssertTrue(host.isPresenterUnavailable)
        XCTAssertFalse(host.currentTimerState.isEnabled)
    }

    private func failingHost() -> (WinSwiftUIWindowHost, FakeRecoveryClock, FakeRenderBackend) {
        let backend = FakeRenderBackend(attachShouldFail: true)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Dashboard", size: IntSize(width: 320, height: 200), clearColor: .black,
                content: [], windowID: "dashboard"),
            renderer: backend, batchRenderer: nil,
            surfaceDescriptorProvider: { _ in
                SurfaceDescriptor(offscreenPixelSize: IntSize(width: 320, height: 200))
            }, startupProbeConfiguration: nil)
        let clock = FakeRecoveryClock(1000)
        host.recoveryClock = { clock.now }
        return (host, clock, backend)
    }

    func testPresenterFailureRunsAfterCallerReturnsAndOnlyOnce() async throws {
        let (host, clock, backend) = failingHost()
        defer {
            host.appFailureHandler = nil
            host.windowWillClose(host.platformWindow)
        }
        let delivered = expectation(description: "settled failure delivered")
        var events: [AppFailure] = []
        var callerReturned = false
        host.appFailureHandler = { failure in
            XCTAssertTrue(callerReturned)
            XCTAssertTrue(host.isPresenterUnavailable)
            XCTAssertFalse(host.isClosed)
            events.append(failure)
            delivered.fulfill()
        }
        exhaustPresenter(host, clock: clock)
        XCTAssertTrue(events.isEmpty)
        let attempts = backend.attachedSurfaces.count
        callerReturned = true
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .presenterUnavailable)
        XCTAssertEqual(events.first?.window?.sceneID, "dashboard")
        XCTAssertEqual(events.first?.window?.title, "Dashboard")
        XCTAssertFalse(try XCTUnwrap(events.first).message.isEmpty)
        backend.setAttachShouldFail(false)
        for _ in 0..<20 {
            clock.now += 30
            host.windowNeedsDisplay(host.platformWindow)
        }
        XCTAssertEqual(backend.attachedSurfaces.count, attempts)
        XCTAssertEqual(events.count, 1)
    }

    func testClosedWindowSuppressesPendingPresenterFailure() async {
        let (host, clock, _) = failingHost()
        let unexpected = expectation(description: "closed host must not report")
        unexpected.isInverted = true
        host.appFailureHandler = { _ in unexpected.fulfill() }
        exhaustPresenter(host, clock: clock)
        host.windowWillClose(host.platformWindow)
        await fulfillment(of: [unexpected], timeout: 0.1)
        XCTAssertTrue(host.isClosed)
    }

    func testRecoveredWindowSuppressesPendingPresenterFailure() async {
        let (host, clock, backend) = failingHost()
        let unexpected = expectation(description: "recovered host must not report")
        unexpected.isInverted = true
        host.appFailureHandler = { _ in unexpected.fulfill() }
        exhaustPresenter(host, clock: clock)
        backend.setAttachShouldFail(false)
        // Explicit embedder reattachment is existing behavior; no automatic
        // extra attempt is made by the failure delivery code.
        host.windowDidCreate(host.platformWindow)
        XCTAssertFalse(host.isPresenterUnavailable)
        await fulfillment(of: [unexpected], timeout: 0.1)
        host.windowWillClose(host.platformWindow)
    }

    func testAsyncFailureHandlerDoesNotKeepClosedHostAlive() async throws {
        let clock = FakeRecoveryClock(1000)
        var retained: WinSwiftUIWindowHost? = failingHost().0
        retained?.recoveryClock = { clock.now }
        weak var weakHost = retained
        let entered = expectation(description: "handler suspended")
        let finished = expectation(description: "handler returned")
        var releaseHandler: CheckedContinuation<Void, Never>?
        retained?.appFailureHandler = { _ in
            await withCheckedContinuation { continuation in
                releaseHandler = continuation
                entered.fulfill()
            }
            finished.fulfill()
        }
        exhaustPresenter(try XCTUnwrap(retained), clock: clock)
        await fulfillment(of: [entered], timeout: 2)
        if let closing = retained { closing.windowWillClose(closing.platformWindow) }
        retained = nil
        XCTAssertNil(weakHost, "Only copied failure values may cross the app callback suspension.")
        let continuation = releaseHandler
        releaseHandler = nil
        continuation?.resume()
        await fulfillment(of: [finished], timeout: 2)
    }

    func testStartupFailureWaitsForSuccessfulStopThenDeliversOnce() async {
        let driver = AppFailureTestDriver()
        let coordinator = driver.coordinator()
        driver.beforeStopReturns = { [weak coordinator] in
            let premature = await coordinator?.deliverStartupFailureAfterCleanup("too early")
            XCTAssertEqual(premature, false)
            XCTAssertTrue(driver.failures.isEmpty)
        }
        do {
            _ = try await coordinator.runNative()
            XCTFail("Startup error must not become successful exit")
        } catch {
            XCTAssertTrue(error is AppFailureTestError)
        }
        XCTAssertEqual(driver.discards, 1)
        XCTAssertEqual(driver.stops, 1)
        XCTAssertEqual(coordinator.windowCount, 0)
        let delivered = await coordinator.deliverStartupFailureAfterCleanup("original failure")
        let duplicate = await coordinator.deliverStartupFailureAfterCleanup("duplicate")
        XCTAssertTrue(delivered)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(driver.failures.count, 1)
        XCTAssertEqual(driver.failures.first?.kind, .startup)
        XCTAssertNil(driver.failures.first?.window)
        XCTAssertEqual(driver.failures.first?.message, "original failure")
        driver.beforeStopReturns = nil
        driver.host = nil
    }

    func testFailedOwnerStartDoesNotPretendCleanupCompleted() async {
        let driver = AppFailureTestDriver()
        driver.startOwnerFails = true
        let coordinator = driver.coordinator()
        do {
            _ = try await coordinator.runNative()
            XCTFail("Expected owner start failure")
        } catch {}
        let delivered = await coordinator.deliverStartupFailureAfterCleanup("start failed")
        XCTAssertFalse(delivered)
        XCTAssertTrue(driver.failures.isEmpty)
        XCTAssertEqual(driver.stops, 0)
        XCTAssertNil(driver.host)
    }

    func testFailedStopDoesNotDeliverStartupFailure() async {
        let driver = AppFailureTestDriver()
        driver.stopFails = true
        let coordinator = driver.coordinator()
        do {
            _ = try await coordinator.runNative()
            XCTFail("Expected cleanup failure")
        } catch {}
        let delivered = await coordinator.deliverStartupFailureAfterCleanup("stop failed")
        XCTAssertFalse(delivered)
        XCTAssertTrue(driver.failures.isEmpty)
        XCTAssertEqual(driver.stops, 1)
        driver.host = nil
    }

    func testFailedRollbackKeepsOwnershipAndSuppressesAppCallback() async {
        let driver = AppFailureTestDriver()
        driver.discardFails = true
        let coordinator = driver.coordinator()
        do {
            _ = try await coordinator.runNative()
            XCTFail("Expected rollback failure")
        } catch {}
        let delivered = await coordinator.deliverStartupFailureAfterCleanup("rollback failed")
        XCTAssertFalse(delivered)
        XCTAssertTrue(driver.failures.isEmpty)
        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(driver.stops, 0)
        let stopped = expectation(description: "simulated owner stop returned")
        driver.afterStopReturns = { stopped.fulfill() }
        // End only the headless fixture with an actual simulated close. The
        // production path does not fabricate this acknowledgement.
        if let host = driver.host { host.windowWillClose(host.platformWindow) }
        driver.host = nil
        await fulfillment(of: [stopped], timeout: 2)
        let afterJoin = await coordinator.deliverStartupFailureAfterCleanup("fatal even after later join")
        XCTAssertFalse(afterJoin)
        XCTAssertTrue(driver.failures.isEmpty)
        XCTAssertEqual(driver.stops, 1)
        driver.afterStopReturns = nil
    }
}
