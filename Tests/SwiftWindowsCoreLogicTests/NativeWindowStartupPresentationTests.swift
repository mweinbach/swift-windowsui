import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

private enum NativeStartupTestStage: Error, Equatable {
    case prepare
    case show
    case activate
    case finishPresentation
}

/// Controlled replies only: no HWND, native thread, sleep, or foreground call.
@MainActor
private final class NativeStartupReplyGate {
    let entered = XCTestExpectation(description: "startup operation awaits its reply")
    private var continuation: CheckedContinuation<Void, any Error>?
    private var result: Result<Void, any Error>?

    func wait() async throws {
        if let result { return try result.get() }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }

    func complete(_ result: Result<Void, any Error> = .success(())) {
        guard self.result == nil else { return }
        self.result = result
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

@MainActor
private final class NativeStartupStageProbe {
    var stages: [NativeStartupTestStage] = []
    var failure: NativeStartupTestStage?
    var activationResult = true
    var showReply: NativeStartupReplyGate?
    var activationReply: NativeStartupReplyGate?

    func perform(_ intent: WindowCoordinatorNativeStartupIntent) async throws {
        try await intent.perform(
            prepare: { try self.record(.prepare) },
            show: {
                try self.record(.show)
                try await self.showReply?.wait()
            },
            activate: {
                try self.record(.activate)
                try await self.activationReply?.wait()
                return self.activationResult
            },
            finishPresentation: { try self.record(.finishPresentation) })
    }

    private func record(_ stage: NativeStartupTestStage) throws {
        stages.append(stage)
        if failure == stage { throw stage }
    }
}

@MainActor
private final class NativeShowOperationProbe {
    var calls: [String] = []
    var previousVisibility = true
    var updateSucceeded = true
    var invalidationFailure: NativeWindowOwnerFailure?
    var geometryFailure: NativeWindowOwnerFailure?

    func execute() throws -> Win32NativeWindowOperationResult {
        try Win32NativeWindowShowOperation.execute(
            enableInteractiveInput: { self.calls.append("enable-input") },
            showWindow: {
                self.calls.append("show")
                return self.previousVisibility
            },
            updateWindow: {
                self.calls.append("update")
                return self.updateSucceeded
            },
            invalidate: {
                self.calls.append("invalidate")
                if let failure = self.invalidationFailure {
                    self.calls.append("capture-invalidation-error")
                    throw failure
                }
            },
            sampleGeometry: {
                self.calls.append("geometry")
                return self.geometryFailure
            })
    }
}

/// Uses the real coordinator and startup selector with headless host callbacks.
/// Its recorded operations are not Win32 execution or frame-submission evidence.
@MainActor
private final class NativeStartupCoordinatorDriver {
    var intents: [WindowCoordinatorNativeStartupIntent] = []
    var starts: [WinSwiftUIWindowHost] = []
    var shown: [WinSwiftUIWindowHost] = []
    var freshlyActivated: [WinSwiftUIWindowHost] = []
    var reactivated: [WinSwiftUIWindowHost] = []
    var finished: [WinSwiftUIWindowHost] = []
    var discarded: [WinSwiftUIWindowHost] = []
    var stops = 0
    var scopes = 0
    var showFailure: NativeStartupTestStage?
    var showReply: NativeStartupReplyGate?
    var discardReply: NativeStartupReplyGate?
    private var unobservedStarts: [WinSwiftUIWindowHost] = []
    private var nextStart: CheckedContinuation<WinSwiftUIWindowHost, Never>?

    func hooks() -> WindowCoordinatorNativeHooks {
        WindowCoordinatorNativeHooks(
            startOwner: {},
            startWindow: { host, intent in
                self.starts.append(host)
                self.intents.append(intent)
                if let observer = self.nextStart {
                    self.nextStart = nil
                    observer.resume(returning: host)
                } else {
                    self.unobservedStarts.append(host)
                }
                try await intent.perform(
                    prepare: { host.windowDidCreate(host.platformWindow) },
                    show: {
                        self.shown.append(host)
                        try await self.showReply?.wait()
                        if let failure = self.showFailure { throw failure }
                    },
                    activate: {
                        self.freshlyActivated.append(host)
                        return false
                    },
                    finishPresentation: { self.finished.append(host) })
            },
            activateWindow: { host in
                self.reactivated.append(host)
                return false
            },
            requestCloseWindow: { host in
                guard host.windowShouldClose(host.platformWindow) else { return }
                host.windowWillClose(host.platformWindow)
            },
            discardFailedWindow: { host in
                self.discarded.append(host)
                try await self.discardReply?.wait()
                host.windowWillClose(host.platformWindow)
            },
            stopOwner: {
                self.stops += 1
                return 0
            })
    }

    func observeStart() async -> WinSwiftUIWindowHost {
        if !unobservedStarts.isEmpty { return unobservedStarts.removeFirst() }
        return await withCheckedContinuation { nextStart = $0 }
    }
}

@MainActor
final class NativeWindowStartupPresentationTests: XCTestCase {
    func testPrimaryLaunchShowsAfterPreparationBeforePresentation() async throws {
        let probe = NativeStartupStageProbe()
        try await probe.perform(.primaryLaunch)
        XCTAssertEqual(probe.stages, [.prepare, .show, .finishPresentation])
    }

    func testRequestedWindowActivatesAfterPreparationBeforePresentation() async throws {
        let probe = NativeStartupStageProbe()
        try await probe.perform(.requestedWindow)
        XCTAssertEqual(probe.stages, [.prepare, .activate, .finishPresentation])
    }

    func testDeclinedRequestedActivationStillFinishesPresentation() async throws {
        let probe = NativeStartupStageProbe()
        probe.activationResult = false
        try await probe.perform(.requestedWindow)
        XCTAssertEqual(probe.stages, [.prepare, .activate, .finishPresentation])
    }

    func testPrimaryLaunchWaitsForShowReplyBeforePresentation() async throws {
        let probe = NativeStartupStageProbe()
        let reply = NativeStartupReplyGate()
        probe.showReply = reply
        defer { reply.complete() }
        let operation = Task { @MainActor in try await probe.perform(.primaryLaunch) }

        let entered = await XCTWaiter.fulfillment(of: [reply.entered], timeout: 2)
        XCTAssertEqual(entered, .completed)
        XCTAssertEqual(probe.stages, [.prepare, .show])
        reply.complete()
        try await operation.value
        XCTAssertEqual(probe.stages, [.prepare, .show, .finishPresentation])
    }

    func testRequestedWindowWaitsForActivationReplyBeforePresentation() async throws {
        let probe = NativeStartupStageProbe()
        let reply = NativeStartupReplyGate()
        probe.activationReply = reply
        defer { reply.complete() }
        let operation = Task { @MainActor in try await probe.perform(.requestedWindow) }

        let entered = await XCTWaiter.fulfillment(of: [reply.entered], timeout: 2)
        XCTAssertEqual(entered, .completed)
        XCTAssertEqual(probe.stages, [.prepare, .activate])
        reply.complete()
        try await operation.value
        XCTAssertEqual(probe.stages, [.prepare, .activate, .finishPresentation])
    }

    func testCancellationDoesNotInventShowCompletion() async throws {
        let probe = NativeStartupStageProbe()
        let reply = NativeStartupReplyGate()
        probe.showReply = reply
        defer { reply.complete() }
        let operation = Task { @MainActor in try await probe.perform(.primaryLaunch) }

        let entered = await XCTWaiter.fulfillment(of: [reply.entered], timeout: 2)
        XCTAssertEqual(entered, .completed)
        operation.cancel()
        XCTAssertTrue(operation.isCancelled)
        XCTAssertEqual(probe.stages, [.prepare, .show])
        reply.complete()
        try await operation.value
        XCTAssertEqual(probe.stages, [.prepare, .show, .finishPresentation])
    }

    func testCancelledShowReplyPropagatesWithoutPresentationOrActivation() async {
        let probe = NativeStartupStageProbe()
        let reply = NativeStartupReplyGate()
        probe.showReply = reply
        defer { reply.complete() }
        let operation = Task { @MainActor in try await probe.perform(.primaryLaunch) }

        let entered = await XCTWaiter.fulfillment(of: [reply.entered], timeout: 2)
        XCTAssertEqual(entered, .completed)
        reply.complete(.failure(CancellationError()))
        do {
            try await operation.value
            XCTFail("A cancelled show reply must not become startup success.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(probe.stages, [.prepare, .show])
    }

    func testPreparationFailureDoesNotShowOrActivate() async {
        for intent in [WindowCoordinatorNativeStartupIntent.primaryLaunch, .requestedWindow] {
            let probe = NativeStartupStageProbe()
            probe.failure = .prepare
            do {
                try await probe.perform(intent)
                XCTFail("Preparation failure must stop startup.")
            } catch {
                XCTAssertEqual(error as? NativeStartupTestStage, .prepare)
            }
            XCTAssertEqual(probe.stages, [.prepare])
        }
    }

    func testShowFailureDoesNotActivateOrFinishPresentation() async {
        let probe = NativeStartupStageProbe()
        probe.failure = .show
        do {
            try await probe.perform(.primaryLaunch)
            XCTFail("Show failure must not trigger activation or presentation.")
        } catch {
            XCTAssertEqual(error as? NativeStartupTestStage, .show)
        }
        XCTAssertEqual(probe.stages, [.prepare, .show])
    }

    func testRequestedActivationFailureDoesNotShowOrFinishPresentation() async {
        let probe = NativeStartupStageProbe()
        probe.failure = .activate
        do {
            try await probe.perform(.requestedWindow)
            XCTFail("Activation failure must not fall back to show.")
        } catch {
            XCTAssertEqual(error as? NativeStartupTestStage, .activate)
        }
        XCTAssertEqual(probe.stages, [.prepare, .activate])
    }

    func testPresentationFailureIsPropagatedAfterTheSelectedOperation() async {
        for intent in [WindowCoordinatorNativeStartupIntent.primaryLaunch, .requestedWindow] {
            let probe = NativeStartupStageProbe()
            probe.failure = .finishPresentation
            do {
                try await probe.perform(intent)
                XCTFail("Presentation failure must remain a startup failure.")
            } catch {
                XCTAssertEqual(error as? NativeStartupTestStage, .finishPresentation)
            }
            XCTAssertEqual(
                probe.stages,
                [.prepare, intent == .primaryLaunch ? .show : .activate, .finishPresentation])
        }
    }

    func testNativeShowExecutesInputShowUpdateInvalidateGeometryInOrder() async throws {
        let probe = NativeShowOperationProbe()
        let result = try probe.execute()
        guard case .completed = result else { return XCTFail("Show must complete without an activation Bool.") }
        XCTAssertEqual(probe.calls, ["enable-input", "show", "update", "invalidate", "geometry"])
    }

    func testNativeShowPreviouslyHiddenReturnIsNotFailure() async throws {
        let probe = NativeShowOperationProbe()
        probe.previousVisibility = false
        let result = try probe.execute()
        guard case .completed = result else { return XCTFail("Previously hidden does not mean showing failed.") }
        XCTAssertEqual(probe.calls, ["enable-input", "show", "update", "invalidate", "geometry"])
    }

    func testNativeShowIgnoredUpdateFailureRemainsIgnored() async throws {
        let probe = NativeShowOperationProbe()
        probe.updateSucceeded = false
        let result = try probe.execute()
        guard case .completed = result else { return XCTFail("This change must not add an UpdateWindow error policy.") }
        XCTAssertEqual(probe.calls, ["enable-input", "show", "update", "invalidate", "geometry"])
    }

    func testNativeShowInvalidationFailureIsCapturedBeforeGeometry() async {
        let probe = NativeShowOperationProbe()
        let failure = NativeWindowOwnerFailure.native(operation: "InvalidateRect", code: 123)
        probe.invalidationFailure = failure
        XCTAssertThrowsError(try probe.execute()) { error in
            XCTAssertEqual(error as? NativeWindowOwnerFailure, failure)
        }
        XCTAssertEqual(probe.calls, ["enable-input", "show", "update", "invalidate", "capture-invalidation-error"])
    }

    func testNativeShowGeometryFailureFollowsSuccessfulInvalidation() async {
        let probe = NativeShowOperationProbe()
        let failure = NativeWindowOwnerFailure.native(operation: "GetClientRect", code: 456)
        probe.geometryFailure = failure
        XCTAssertThrowsError(try probe.execute()) { error in
            XCTAssertEqual(error as? NativeWindowOwnerFailure, failure)
        }
        XCTAssertEqual(probe.calls, ["enable-input", "show", "update", "invalidate", "geometry"])
    }

    func testNativeShowCompletesWhenBothIgnoredBooleanResultsAreFalse() async throws {
        let probe = NativeShowOperationProbe()
        probe.previousVisibility = false
        probe.updateSucceeded = false
        let result = try probe.execute()
        guard case .completed = result else { return XCTFail("Neither ignored Bool is a new failure condition.") }
        XCTAssertEqual(probe.calls, ["enable-input", "show", "update", "invalidate", "geometry"])
    }

    func testCoordinatorMarksOnlyPrimaryLaunchForShow() async throws {
        let driver = NativeStartupCoordinatorDriver()
        let coordinator = makeCoordinator(driver)
        defer { closeAllWindows(coordinator) }
        let run = Task { @MainActor in try await coordinator.runNative() }
        let primary = await driver.observeStart()
        _ = try await coordinator.bootPrimaryNativeWindow()
        let settingsRequest = try XCTUnwrap(coordinator.beginNativeSettingsRequest())
        let settings = try await settingsRequest.value
        let valuePayload = WindowActionPayload(id: "value", value: AnyHashable("same"))
        let valueRequest = try XCTUnwrap(coordinator.beginNativeWindowRequest(payload: valuePayload))
        let valueWindow = try await valueRequest.value

        XCTAssertEqual(driver.intents, [.primaryLaunch, .requestedWindow, .requestedWindow])
        XCTAssertEqual(driver.shown.count, 1)
        XCTAssertTrue(driver.shown.first === primary)
        XCTAssertEqual(driver.freshlyActivated.count, 2)
        XCTAssertTrue(driver.freshlyActivated.contains { $0 === settings })
        XCTAssertTrue(driver.freshlyActivated.contains { $0 === valueWindow })
        XCTAssertEqual(driver.finished.count, 3)

        let settingsFound = try await coordinator.openNativeSettings()
        let valueFound = try await coordinator.openNativeWindow(payload: valuePayload)
        XCTAssertTrue(settingsFound)
        XCTAssertTrue(valueFound)
        XCTAssertEqual(driver.starts.count, 3)
        XCTAssertEqual(driver.reactivated.count, 2)
        XCTAssertTrue(driver.reactivated.contains { $0 === settings })
        XCTAssertTrue(driver.reactivated.contains { $0 === valueWindow })
        XCTAssertEqual(coordinator.lastNativeActivationResult(for: settings), false)
        XCTAssertEqual(coordinator.lastNativeActivationResult(for: valueWindow), false)

        closeAllWindows(coordinator)
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(driver.stops, 1)
    }

    func testCoordinatorShowFailureWaitsForRollbackBeforeOwnerStop() async {
        let driver = NativeStartupCoordinatorDriver()
        let rollback = NativeStartupReplyGate()
        driver.showFailure = .show
        driver.discardReply = rollback
        let coordinator = makeCoordinator(driver)
        defer {
            rollback.complete()
            closeAllWindows(coordinator)
        }
        let run = Task { @MainActor in try await coordinator.runNative() }

        let entered = await XCTWaiter.fulfillment(of: [rollback.entered], timeout: 2)
        XCTAssertEqual(entered, .completed)
        XCTAssertEqual(driver.intents, [.primaryLaunch])
        XCTAssertEqual(driver.discarded.count, 1)
        XCTAssertTrue(driver.finished.isEmpty)
        XCTAssertTrue(driver.freshlyActivated.isEmpty)
        XCTAssertEqual(driver.stops, 0)
        rollback.complete()
        do {
            _ = try await run.value
            XCTFail("The coordinator must preserve the show error after rollback.")
        } catch {
            XCTAssertEqual(error as? NativeStartupTestStage, .show)
        }
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(driver.stops, 1)
    }

    func testCoordinatorCancellationStillAwaitsShowAndPresentation() async throws {
        let driver = NativeStartupCoordinatorDriver()
        let reply = NativeStartupReplyGate()
        driver.showReply = reply
        let coordinator = makeCoordinator(driver)
        defer {
            reply.complete()
            closeAllWindows(coordinator)
        }
        let run = Task { @MainActor in try await coordinator.runNative() }

        let entered = await XCTWaiter.fulfillment(of: [reply.entered], timeout: 2)
        XCTAssertEqual(entered, .completed)
        run.cancel()
        XCTAssertTrue(run.isCancelled)
        XCTAssertTrue(driver.finished.isEmpty)
        XCTAssertEqual(driver.stops, 0)
        reply.complete()
        _ = try await coordinator.bootPrimaryNativeWindow()
        XCTAssertEqual(driver.finished.count, 1)
        XCTAssertTrue(driver.freshlyActivated.isEmpty)
        closeAllWindows(coordinator)
        let exitCode = try await run.value
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(driver.stops, 1)
    }

    private func makeCoordinator(_ driver: NativeStartupCoordinatorDriver) -> WinSwiftUIWindowCoordinator {
        var settings = WindowGroupConfiguration(
            title: "Settings", size: IntSize(width: 300, height: 200), clearColor: .black, content: [])
        settings.isSettingsWindow = true
        return WinSwiftUIWindowCoordinator(
            sceneConfigurations: [
                WindowGroupConfiguration(
                    title: "Primary", size: IntSize(width: 640, height: 480), clearColor: .black, content: [],
                    windowID: "main"),
                settings,
                WindowGroupConfiguration(
                    title: "Value", size: IntSize(width: 300, height: 200), clearColor: .black, content: [],
                    windowID: "value", forType: String.self, dataBoundContent: { _ in [] }),
            ],
            nativeHooks: driver.hooks(),
            hostFactory: { configuration, _ in
                WinSwiftUIWindowHost(
                    configuration: configuration, renderer: FakeRenderBackend(), batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in
                        SurfaceDescriptor(offscreenPixelSize: IntSize(width: 640, height: 480))
                    },
                    startupProbeConfiguration: nil)
            },
            sceneStorageScopeProvider: {
                driver.scopes += 1
                return "startup-intent-test-\(driver.scopes)"
            })
    }

    private func closeAllWindows(_ coordinator: WinSwiftUIWindowCoordinator) {
        for window in coordinator.windows.reversed() {
            window.host.windowWillClose(window.host.platformWindow)
        }
    }
}
