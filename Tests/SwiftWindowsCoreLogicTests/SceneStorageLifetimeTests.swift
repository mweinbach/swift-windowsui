import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class SceneStorageReleaseLog {
    var releases = 0
    var duringRelease: (@MainActor () -> Void)?
}

@MainActor
private final class SceneStoragePayload {
    let number: Int
    let log: SceneStorageReleaseLog

    init(_ number: Int, log: SceneStorageReleaseLog) {
        self.number = number
        self.log = log
    }

    isolated deinit {
        log.releases += 1
        log.duringRelease?()
    }
}

private enum SceneStorageStartupFailure: Error {
    case rejected
}

private struct ClosingSceneStorageRawValue: RawRepresentable {
    let value: String
    let onRawValue: (@MainActor () -> Void)?

    init(rawValue: String) {
        self.value = rawValue
        self.onRawValue = nil
    }

    init(_ value: String, onRawValue: @escaping @MainActor () -> Void) {
        self.value = value
        self.onRawValue = onRawValue
    }

    var rawValue: String {
        MainActor.assumeIsolated { onRawValue?() }
        return value
    }
}

/// Uses the real coordinator and retained host lifecycle, but never creates an
/// HWND, enters a message loop, or asks the GPU to present.
@MainActor
private final class SceneStorageLifetimeHarness {
    let recorder = HostEnvironmentRecorder()
    var startedHosts: [WinSwiftUIWindowHost] = []
    var beforeStartReturns: (@MainActor (WinSwiftUIWindowHost) throws -> Void)?

    func makeCoordinator(scope: String = UUID().uuidString) -> WinSwiftUIWindowCoordinator {
        WinSwiftUIWindowCoordinator(
            sceneConfigurations: [
                WindowGroupConfiguration(
                    title: "Scene storage lifetime", size: IntSize(width: 100, height: 100),
                    clearColor: .black,
                    content: [AnyView(HostEnvironmentProbeView(recorder: recorder))],
                    windowID: "document")
            ],
            hooks: WindowCoordinatorHooks(
                startWindow: { [self] host in
                    startedHosts.append(host)
                    host.windowDidCreate(host.platformWindow)
                    try beforeStartReturns?(host)
                },
                requestCloseWindow: { host in
                    guard host.windowShouldClose(host.platformWindow) else { return }
                    host.windowWillClose(host.platformWindow)
                },
                runMessageLoop: { 0 },
                terminateMessageLoop: {}
            ),
            hostFactory: { configuration, _ in
                WinSwiftUIWindowHost(
                    configuration: configuration, renderer: FakeRenderBackend(), batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in
                        SurfaceDescriptor(
                            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1))!,
                            pixelSize: IntSize(width: 100, height: 100), scaleFactor: 1)
                    },
                    startupProbeConfiguration: nil)
            },
            sceneStorageScopeProvider: { scope })
    }

    func context(_ environment: EnvironmentValues) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { Size(width: 100, height: 100) },
            invalidateHandler: {}, environmentValuesProvider: { environment })
    }

    func payloadBinding(in environment: EnvironmentValues, key: String = "payload") -> Binding<SceneStoragePayload?> {
        let storage = SceneStorage<SceneStoragePayload?>(wrappedValue: nil, key)
        return ViewBuildContextScope.withCurrent(context(environment)) {
            // Establish the same first-read installation path supported before
            // this regression; the separate projection test covers no read.
            _ = storage.wrappedValue
            return storage.projectedValue
        }
    }
}

@MainActor
final class SceneStorageLifetimeTests: XCTestCase {
    func testCloseReleasesStoredPayloadWhileHostEnvironmentAndBindingEscape() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let coordinator = harness.makeCoordinator()
            let host = try coordinator.bootPrimaryWindow()
            let environment = try XCTUnwrap(harness.recorder.snapshots.last)
            let binding = harness.payloadBinding(in: environment)
            let log = SceneStorageReleaseLog()
            weak var weakPayload: SceneStoragePayload?
            do {
                let payload = SceneStoragePayload(1, log: log)
                weakPayload = payload
                binding.wrappedValue = payload
            }
            XCTAssertNotNil(weakPayload)
            XCTAssertEqual(binding.wrappedValue?.number, 1)

            host.windowWillClose(host.platformWindow)

            XCTAssertTrue(host.isClosed)
            XCTAssertEqual(coordinator.windowCount, 0)
            XCTAssertNil(weakPayload)
            XCTAssertEqual(log.releases, 1)
            XCTAssertNil(binding.wrappedValue)
            weak var rejectedPayload: SceneStoragePayload?
            do {
                let payload = SceneStoragePayload(2, log: log)
                rejectedPayload = payload
                binding.wrappedValue = payload
            }
            XCTAssertNil(rejectedPayload)
            XCTAssertEqual(log.releases, 2)
            let reconstructed = harness.payloadBinding(in: environment)
            XCTAssertNil(reconstructed.wrappedValue)
            withExtendedLifetime((host, environment, binding, reconstructed)) {}
        }
    }

    func testRepeatedWindowCloseDoesNotRetainPayloadOrReuseRetiredStringScope() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let coordinator = harness.makeCoordinator(scope: "reused-\(UUID().uuidString)")
            let primary = try coordinator.bootPrimaryWindow()
            let primaryEnvironment = try XCTUnwrap(harness.recorder.snapshots.last)
            let primaryBinding = harness.payloadBinding(in: primaryEnvironment)
            let primaryLog = SceneStorageReleaseLog()
            primaryBinding.wrappedValue = SceneStoragePayload(-1, log: primaryLog)
            let log = SceneStorageReleaseLog()
            var retiredBindings: [Binding<SceneStoragePayload?>] = []
            for index in 0..<12 {
                coordinator.openWindow(payload: WindowActionPayload(id: "document"))
                let child = try XCTUnwrap(harness.startedHosts.last)
                XCTAssertFalse(child === primary)
                let environment = try XCTUnwrap(harness.recorder.snapshots.last)
                XCTAssertEqual(environment.sceneStorageScope, primaryEnvironment.sceneStorageScope)
                let binding = harness.payloadBinding(in: environment)
                XCTAssertNil(binding.wrappedValue)
                weak var payload: SceneStoragePayload?
                do {
                    let value = SceneStoragePayload(index, log: log)
                    payload = value
                    binding.wrappedValue = value
                }
                XCTAssertNotNil(payload)
                child.windowWillClose(child.platformWindow)
                XCTAssertNil(payload)
                XCTAssertNil(binding.wrappedValue)
                XCTAssertEqual(log.releases, index + 1)
                XCTAssertEqual(primaryBinding.wrappedValue?.number, -1)
                XCTAssertEqual(primaryLog.releases, 0)
                retiredBindings.append(binding)
            }
            XCTAssertEqual(coordinator.windowCount, 1)
            primary.windowWillClose(primary.platformWindow)
            XCTAssertEqual(primaryLog.releases, 1)
            XCTAssertTrue(retiredBindings.allSatisfy { $0.wrappedValue == nil })
        }
    }

    func testReconstructedWrappersShareLiveWindowAndEscapedBindingKeepsItsOriginalOwner() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let coordinator = harness.makeCoordinator()
            let firstHost = try coordinator.bootPrimaryWindow()
            let firstEnvironment = try XCTUnwrap(harness.recorder.snapshots.last)
            let storage = SceneStorage<SceneStoragePayload?>(wrappedValue: nil, "payload")
            let firstContext = harness.context(firstEnvironment)
            let retiredStorage = SceneStorage<SceneStoragePayload?>(wrappedValue: nil, "payload")
            _ = ViewBuildContextScope.withCurrent(firstContext) { retiredStorage.wrappedValue }
            let originalBinding = ViewBuildContextScope.withCurrent(firstContext) {
                _ = storage.wrappedValue
                return storage.projectedValue
            }
            let log = SceneStorageReleaseLog()
            originalBinding.wrappedValue = SceneStoragePayload(10, log: log)
            let reconstructed = harness.payloadBinding(in: firstEnvironment)
            XCTAssertEqual(reconstructed.wrappedValue?.number, 10)

            coordinator.openWindow(payload: WindowActionPayload(id: "document"))
            let secondHost = try XCTUnwrap(harness.startedHosts.last)
            let secondEnvironment = try XCTUnwrap(harness.recorder.snapshots.last)
            let secondContext = harness.context(secondEnvironment)
            let secondBinding = harness.payloadBinding(in: secondEnvironment)
            XCTAssertNil(secondBinding.wrappedValue)
            _ = ViewBuildContextScope.withCurrent(secondContext) { storage.wrappedValue }
            ViewBuildContextScope.withCurrent(secondContext) {
                XCTAssertEqual(originalBinding.wrappedValue?.number, 10)
                originalBinding.wrappedValue = SceneStoragePayload(11, log: log)
            }
            XCTAssertEqual(reconstructed.wrappedValue?.number, 11)
            XCTAssertNil(secondBinding.wrappedValue)
            firstHost.windowWillClose(firstHost.platformWindow)
            ViewBuildContextScope.withCurrent(secondContext) {
                originalBinding.wrappedValue = SceneStoragePayload(12, log: log)
                XCTAssertNil(originalBinding.wrappedValue)
                XCTAssertNil(retiredStorage.wrappedValue)
                retiredStorage.wrappedValue = SceneStoragePayload(13, log: log)
            }
            XCTAssertNil(secondBinding.wrappedValue)
            secondHost.windowWillClose(secondHost.platformWindow)
            XCTAssertEqual(log.releases, 4)
        }
    }

    func testStartupRollbackReleasesPayloadAndRevokesEscapedBinding() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let log = SceneStorageReleaseLog()
            weak var payload: SceneStoragePayload?
            var escaped: Binding<SceneStoragePayload?>?
            harness.beforeStartReturns = { [weak harness] _ in
                let harness = try XCTUnwrap(harness)
                let environment = try XCTUnwrap(harness.recorder.snapshots.last)
                let binding = harness.payloadBinding(in: environment)
                let value = SceneStoragePayload(1, log: log)
                payload = value
                binding.wrappedValue = value
                escaped = binding
                throw SceneStorageStartupFailure.rejected
            }
            let coordinator = harness.makeCoordinator()
            XCTAssertThrowsError(try coordinator.bootPrimaryWindow())
            XCTAssertEqual(coordinator.windowCount, 0)
            XCTAssertTrue(try XCTUnwrap(harness.startedHosts.first).isClosed)
            XCTAssertNil(payload)
            XCTAssertEqual(log.releases, 1)
            XCTAssertNil(try XCTUnwrap(escaped).wrappedValue)
        }
    }

    func testHostDeinitWithoutCloseReleasesPayloadDespiteEscapedEnvironment() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            var coordinator: WinSwiftUIWindowCoordinator? = harness.makeCoordinator()
            weak var host: WinSwiftUIWindowHost?
            do {
                host = try XCTUnwrap(coordinator).bootPrimaryWindow()
            }
            let environment = try XCTUnwrap(harness.recorder.snapshots.last)
            let binding = harness.payloadBinding(in: environment)
            let log = SceneStorageReleaseLog()
            weak var payload: SceneStoragePayload?
            do {
                let value = SceneStoragePayload(1, log: log)
                payload = value
                binding.wrappedValue = value
            }
            XCTAssertNotNil(payload)
            harness.startedHosts.removeAll()
            coordinator = nil
            XCTAssertNil(host)
            XCTAssertNil(payload)
            XCTAssertEqual(log.releases, 1)
            XCTAssertNil(binding.wrappedValue)
            withExtendedLifetime((environment, binding, harness)) {}
        }
    }

    func testPayloadReleaseCannotRepopulateRetiredStorage() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let coordinator = harness.makeCoordinator()
            let host = try coordinator.bootPrimaryWindow()
            let environment = try XCTUnwrap(harness.recorder.snapshots.last)
            let binding = harness.payloadBinding(in: environment)
            let log = SceneStorageReleaseLog()
            let rejectedLog = SceneStorageReleaseLog()
            weak var replacement: SceneStoragePayload?
            log.duringRelease = {
                XCTAssertTrue(host.isClosed)
                XCTAssertNil(binding.wrappedValue)
                let value = SceneStoragePayload(2, log: rejectedLog)
                replacement = value
                binding.wrappedValue = value
                let reconstructed = harness.payloadBinding(in: environment)
                reconstructed.wrappedValue = value
                XCTAssertNil(reconstructed.wrappedValue)
            }
            binding.wrappedValue = SceneStoragePayload(1, log: log)
            host.windowWillClose(host.platformWindow)
            XCTAssertEqual(log.releases, 1)
            XCTAssertEqual(rejectedLog.releases, 1)
            XCTAssertNil(replacement)
            XCTAssertNil(binding.wrappedValue)
            log.duringRelease = nil
        }
    }

    func testProjectionWithoutPriorReadBindsTheWindowAndRetires() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let coordinator = harness.makeCoordinator()
            let host = try coordinator.bootPrimaryWindow()
            let environment = try XCTUnwrap(harness.recorder.snapshots.last)
            let key = "projection-\(UUID().uuidString)"
            let storage = SceneStorage<SceneStoragePayload?>(wrappedValue: nil, key)
            let binding = ViewBuildContextScope.withCurrent(harness.context(environment)) { storage.projectedValue }
            let log = SceneStorageReleaseLog()
            weak var payload: SceneStoragePayload?
            do {
                let value = SceneStoragePayload(1, log: log)
                payload = value
                binding.wrappedValue = value
            }
            XCTAssertEqual(harness.payloadBinding(in: environment, key: key).wrappedValue?.number, 1)
            XCTAssertNil(SceneStorage<SceneStoragePayload?>(wrappedValue: nil, key).wrappedValue)
            host.windowWillClose(host.platformWindow)
            XCTAssertNil(payload)
            XCTAssertEqual(log.releases, 1)
        }
    }

    func testRawValueConversionThatClosesWindowCannotWriteAfterRetirement() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let coordinator = harness.makeCoordinator()
            let host = try coordinator.bootPrimaryWindow()
            let environment = try XCTUnwrap(harness.recorder.snapshots.last)
            let storage = SceneStorage(wrappedValue: ClosingSceneStorageRawValue(rawValue: "default"), "raw")
            let binding = ViewBuildContextScope.withCurrent(harness.context(environment)) {
                _ = storage.wrappedValue
                return storage.projectedValue
            }
            var conversions = 0
            binding.wrappedValue = ClosingSceneStorageRawValue("late") {
                conversions += 1
                host.windowWillClose(host.platformWindow)
            }
            XCTAssertEqual(conversions, 1)
            XCTAssertTrue(host.isClosed)
            XCTAssertEqual(binding.wrappedValue.value, "default")
            let raw = SceneStorage(wrappedValue: "absent", "raw")
            XCTAssertEqual(
                ViewBuildContextScope.withCurrent(harness.context(environment)) { raw.wrappedValue }, "absent")
        }
    }

    func testEnvironmentProviderClosingPreviousWindowCannotRebindRetiredWrapper() async throws {
        try await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let coordinator = harness.makeCoordinator()
            let firstHost = try coordinator.bootPrimaryWindow()
            let firstEnvironment = try XCTUnwrap(harness.recorder.snapshots.last)
            let storage = SceneStorage<SceneStoragePayload?>(wrappedValue: nil, "payload")
            _ = ViewBuildContextScope.withCurrent(harness.context(firstEnvironment)) { storage.wrappedValue }
            coordinator.openWindow(payload: WindowActionPayload(id: "document"))
            let secondHost = try XCTUnwrap(harness.startedHosts.last)
            let secondEnvironment = try XCTUnwrap(harness.recorder.snapshots.last)
            let secondBinding = harness.payloadBinding(in: secondEnvironment)
            let log = SceneStorageReleaseLog()
            weak var payload: SceneStoragePayload?
            do {
                let value = SceneStoragePayload(1, log: log)
                payload = value
                storage.wrappedValue = value
            }
            var providerCalls = 0
            let closingContext = ViewBuildContext(
                canvasSizeProvider: { Size(width: 100, height: 100) }, invalidateHandler: {},
                environmentValuesProvider: {
                    providerCalls += 1
                    firstHost.windowWillClose(firstHost.platformWindow)
                    return secondEnvironment
                })
            XCTAssertNil(ViewBuildContextScope.withCurrent(closingContext) { storage.wrappedValue })
            XCTAssertEqual(providerCalls, 1)
            XCTAssertNil(payload)
            XCTAssertEqual(log.releases, 1)
            storage.wrappedValue = SceneStoragePayload(2, log: log)
            XCTAssertEqual(log.releases, 2)
            XCTAssertNil(secondBinding.wrappedValue)
            XCTAssertFalse(secondHost.isClosed)
            secondHost.windowWillClose(secondHost.platformWindow)
        }
    }

    func testProjectionCreatedBeforeBuildAcquiresItsFirstWindowAndRetires() async throws {
        try await MainActor.run {
            let key = "deferred-\(UUID().uuidString)"
            let storage = SceneStorage<SceneStoragePayload?>(wrappedValue: nil, key)
            let binding = storage.projectedValue
            let harness = SceneStorageLifetimeHarness()
            let coordinator = harness.makeCoordinator()
            let host = try coordinator.bootPrimaryWindow()
            let environment = try XCTUnwrap(harness.recorder.snapshots.last)
            XCTAssertNil(ViewBuildContextScope.withCurrent(harness.context(environment)) { binding.wrappedValue })
            let log = SceneStorageReleaseLog()
            weak var payload: SceneStoragePayload?
            do {
                let value = SceneStoragePayload(1, log: log)
                payload = value
                binding.wrappedValue = value
            }
            XCTAssertEqual(harness.payloadBinding(in: environment, key: key).wrappedValue?.number, 1)
            XCTAssertNil(SceneStorage<SceneStoragePayload?>(wrappedValue: nil, key).wrappedValue)
            host.windowWillClose(host.platformWindow)
            XCTAssertNil(payload)
            XCTAssertEqual(log.releases, 1)
            XCTAssertNil(binding.wrappedValue)
        }
    }

    func testLegacyStringOnlyScopesKeepDeferredBindingAndContextBehavior() async {
        await MainActor.run {
            let harness = SceneStorageLifetimeHarness()
            let key = "legacy-\(UUID().uuidString)"
            let storage = SceneStorage<Int?>(key)
            let binding = storage.projectedValue
            let firstContext = harness.context(EnvironmentValues(sceneStorageScope: "first-\(key)"))
            let secondContext = harness.context(EnvironmentValues(sceneStorageScope: "second-\(key)"))
            XCTAssertNil(ViewBuildContextScope.withCurrent(firstContext) { binding.wrappedValue })
            binding.wrappedValue = 7
            XCTAssertEqual(ViewBuildContextScope.withCurrent(firstContext) { binding.wrappedValue }, 7)
            XCTAssertNil(ViewBuildContextScope.withCurrent(secondContext) { binding.wrappedValue })
            binding.wrappedValue = 8
            XCTAssertEqual(ViewBuildContextScope.withCurrent(firstContext) { binding.wrappedValue }, 7)
            ViewBuildContextScope.withCurrent(secondContext) { binding.wrappedValue = 9 }
            XCTAssertEqual(ViewBuildContextScope.withCurrent(firstContext) { binding.wrappedValue }, 9)
            let projectedElsewhere = ViewBuildContextScope.withCurrent(secondContext) { storage.projectedValue }
            projectedElsewhere.wrappedValue = 10
            XCTAssertEqual(ViewBuildContextScope.withCurrent(firstContext) { binding.wrappedValue }, 10)
            binding.wrappedValue = nil
            XCTAssertEqual(ViewBuildContextScope.withCurrent(secondContext) { binding.wrappedValue }, 8)
            binding.wrappedValue = nil
            XCTAssertNil(SceneStorage<Int?>(key).wrappedValue)
        }
    }
}
