import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform

@MainActor
private final class NativeOwnedSmokeModel: ObservableObject {
    @Published private(set) var phase = 0
    private var shared: NativeOwnedSmokeSharedState?
    private var hasStarted = false
    private var first: CheckedContinuation<Void, any Error>?
    private var second: CheckedContinuation<Void, any Error>?

    func bind(_ shared: NativeOwnedSmokeSharedState) { self.shared = shared }

    func run() async {
        guard let shared else { return }
        guard !hasStarted else {
            shared.fail(NativeOwnedSmokeFailure("model-task-started-more-than-once"))
            return
        }
        hasStarted = true
        shared.observation.record(.modelStarted)
        do {
            try await pause(first: true)
            try Task.checkCancellation()
            phase = 1
            shared.observation.record(.modelFirstResumed)
            try await pause(first: false)
            try Task.checkCancellation()
            phase = 2
            shared.observation.record(.modelSecondResumed)
            shared.observation.record(.modelFinished)
        } catch {
            shared.fail(NativeOwnedSmokeFailure("mounted-model-task-cancelled-or-failed", error: error))
        }
    }

    private func pause(first isFirst: Bool) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if isFirst {
                    first = continuation
                    shared?.observation.record(.modelFirstAwait)
                } else {
                    second = continuation
                    shared?.observation.record(.modelSecondAwait)
                }
            }
        } onCancel: { [self] in
            Task { @MainActor in cancelWaits() }
        }
    }

    private func cancelWaits() {
        let first = self.first
        let second = self.second
        self.first = nil
        self.second = nil
        first?.resume(throwing: CancellationError())
        second?.resume(throwing: CancellationError())
    }

    func releaseFirst() {
        guard let first else {
            shared?.fail(NativeOwnedSmokeFailure("first-model-await-was-not-parked"))
            return
        }
        self.first = nil
        shared?.observation.record(.modelFirstReleased)
        first.resume()
    }

    func releaseSecond() {
        guard let second else {
            shared?.fail(NativeOwnedSmokeFailure("second-model-await-was-not-parked"))
            return
        }
        self.second = nil
        shared?.observation.record(.modelSecondReleased)
        second.resume()
    }
}

@MainActor
private struct NativeOwnedSmokeContent: View {
    @ObservedObject var model: NativeOwnedSmokeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Native smoke stage \(model.phase)")
                .accessibilityIdentifier("owned-native-smoke-stage")
            List(Array(0..<64), id: \.self) { row in
                Text("Owned row \(row)")
            }
            .frame(height: 260)
        }
        .padding(16)
        .task { await model.run() }
    }
}

@MainActor
private struct NativeOwnedSmokeApplication: App {
    let model = NativeOwnedSmokeModel()

    init() {}

    var body: some Scene {
        WindowGroup("Owned native scheduling fixture", size: IntSize(width: 560, height: 380)) {
            NativeOwnedSmokeContent(model: model)
        }
    }
}

/// This fixture uses the real App scene, coordinator, host, runtime, owner and
/// native factory. Its only bootstrap difference is the existing injection
/// seam that explicitly disables persisted pacing and startup-probe settings.
/// After provider acquisition, fixture-only setup can hold normal ingress
/// delivery; the original explicit query and production turn rules are unchanged.
@MainActor
final class NativeOwnedSmokeSession {
    nonisolated let shared: NativeOwnedSmokeSharedState
    nonisolated let pump: Win32NativePump
    private let renderBackendFactory: any RenderBackendFactory
    private let app: NativeOwnedSmokeApplication
    private let probe: NativeOwnedSmokeHostProbe
    private var coordinator: WinSwiftUIWindowCoordinator?
    private var host: WinSwiftUIWindowHost?
    private var workloadStarted = false

    init(shared: NativeOwnedSmokeSharedState, renderBackendFactory: any RenderBackendFactory) {
        self.shared = shared
        self.renderBackendFactory = renderBackendFactory
        pump = Win32NativePump(observation: shared.observation)
        app = NativeOwnedSmokeApplication()
        app.model.bind(shared)
        probe = NativeOwnedSmokeHostProbe(shared: shared)
    }

    func run() async {
        guard let nativeFactory = renderBackendFactory.makeNativePresentationFactory() else {
            shared.fail(NativeOwnedSmokeFailure("native-presentation-factory-unavailable"))
            return
        }
        let platform = Win32PlatformHostFactory()
        var hooks = WindowCoordinatorNativeHooks.win32(pump)
        let startWindow = hooks.startWindow
        hooks.startWindow = { [shared] host, intent in
            try await startWindow(host, intent)
            shared.observation.record(
                .hostReady, windowKey: host.platformWindow.nativeWindowKey,
                generation: host.platformWindow.nativeSurface?.generation)
        }
        let stopOwner = hooks.stopOwner
        hooks.stopOwner = { [shared] in
            shared.ingressSetup.abort()
            let code = try await stopOwner()
            shared.observation.record(.actorStopConsumed, value: Int64(code))
            return code
        }
        let coordinator = WinSwiftUIWindowCoordinator(
            sceneConfigurations: app.body.makeWindowConfigurations(),
            renderBackendFactory: renderBackendFactory, platformHostFactory: platform,
            nativeHooks: hooks, nativePresentationFactory: nativeFactory,
            hostFactory: { [weak self] configuration, _ in
                guard let self else { throw NativeWindowOwnerFailure.unavailable }
                guard self.host == nil else { throw NativeOwnedSmokeFailure("more-than-one-window-requested") }
                let windowConfiguration = WinSwiftUIWindowHost.platformWindowConfiguration(for: configuration)
                guard let window = try platform.makeWindow(configuration: windowConfiguration) as? Win32Window else {
                    throw NativeWindowOwnerFailure.unavailable
                }
                try window.installNativeSmokeIngressSetup(self.shared.ingressSetup)
                let host = WinSwiftUIWindowHost(
                    configuration: configuration, platformWindow: window,
                    renderer: self.renderBackendFactory.makeRenderBackend(),
                    batchRenderer: self.renderBackendFactory.makeBatchRenderBackend(),
                    nativePresentationFactory: nativeFactory,
                    startupPresentationMode: .automatic, startupProbeConfiguration: nil,
                    presentPacingMemory: nil)
                host.nativeSmokeProbe = self.probe
                self.probe.noteAdoptedContent(phase: self.app.model.phase, revision: host.hostedRuntime.contentRevision)
                host.onReloadContentCompleted = { [weak host, weak self] in
                    guard let host, let self else { return }
                    self.probe.noteAdoptedContent(
                        phase: self.app.model.phase, revision: host.hostedRuntime.contentRevision)
                }
                self.host = host
                return host
            },
            sceneStorageScopeProvider: { "owned-native-smoke" }, liveDiagnostics: nil)
        self.coordinator = coordinator
        do {
            let code = try await coordinator.runNative()
            shared.recordOwnerExit(code)
            shared.observation.record(.coordinatorReturned, value: Int64(code))
        } catch {
            shared.fail(NativeOwnedSmokeFailure("native-coordinator-failed", error: error))
        }
        withExtendedLifetime(app) {}
        withExtendedLifetime(coordinator) {}
    }

    func startWorkload() async {
        guard !workloadStarted, let host, let key = host.platformWindow.nativeWindowKey else {
            shared.fail(NativeOwnedSmokeFailure("workload-window-unavailable-or-duplicate"))
            return
        }
        workloadStarted = true
        do {
            let provider = try await host.acquireNativeSmokeProvider()
            guard shared.installProvider(provider, windowKey: key) else {
                throw NativeOwnedSmokeFailure("provider-installed-more-than-once")
            }
            probe.armNestedQuery(provider)
            shared.observation.record(.providerAcquired, windowKey: key)
            guard shared.ingressSetup.arm(windowKey: key) else { return }
            var admitted: UInt64 = 0
            for ordinal in UInt32(0)..<UInt32(64) {
                let requestID = NativeWindowRequestID()
                shared.ingressSetup.register(ordinal: ordinal, requestID: requestID, windowKey: key)
                let reply = NativeWindowReply<NativeWindowSurface> { [shared] result in
                    shared.recordReply(ordinal: ordinal, requestID: requestID, result: result)
                }
                let command = Win32NativeSmokeCommand(
                    windowKey: key, requestID: requestID, ordinal: ordinal, provider: provider,
                    observation: shared.observation, reply: reply)
                switch pump.submit(command) {
                case .accepted: admitted += 1
                case .rejected: break  // The command's real rejection callback records the exact failure.
                }
            }
            shared.observation.record(.ownedWorkloadSubmitted, windowKey: key, auxiliary: admitted)
            if admitted != 64 { shared.fail(NativeOwnedSmokeFailure("owned-workload-was-not-fully-admitted")) }
        } catch {
            shared.fail(NativeOwnedSmokeFailure("provider-acquisition-failed", error: error))
        }
    }

    func releaseFirst() {
        shared.ingressSetup.requestFirstRelease { [weak model = app.model] in
            guard let model else { return .unavailable }
            model.releaseFirst()
            return .invoked
        }
    }

    func releaseSecond() { app.model.releaseSecond() }

    func sampleIdleBoundary(ending: Bool) {
        guard let host else {
            shared.fail(NativeOwnedSmokeFailure("idle-host-unavailable"))
            return
        }
        host.whenNativeSmokePresentationDrained { [weak host, shared, app] in
            guard let host else {
                shared.fail(NativeOwnedSmokeFailure("idle-host-was-released"))
                return
            }
            guard shared.ingressSetup.isIdleReady else {
                shared.fail(NativeOwnedSmokeFailure("idle-ingress-setup-was-not-open"))
                return
            }
            let snapshot = host.nativeSmokeSnapshot(phase: app.model.phase)
            shared.recordIdle(snapshot, ending: ending)
            shared.observation.record(
                ending ? .idleEnded : .idleBegan, windowKey: host.platformWindow.nativeWindowKey,
                generation: snapshot.surfaceGeneration, nativeSequence: snapshot.receivedNativeSequence,
                revision: snapshot.contentRevision, flags: snapshot.isSettled ? 1 : 0)
        }
    }

    func requestClose() {
        shared.ingressSetup.abort()
        guard let host, coordinator?.windowCount == 1 else {
            shared.fail(NativeOwnedSmokeFailure("last-window-close-was-not-owned"))
            return
        }
        host.platformWindow.requestClose()
    }

    func submitAfterOwnerStopped() {
        let snapshot = shared.snapshot()
        guard let key = snapshot.windowKey, let provider = snapshot.provider else {
            shared.fail(NativeOwnedSmokeFailure("late-command-fixture-unavailable"))
            return
        }
        let reply = NativeWindowReply<NativeWindowSurface> { [shared] result in shared.recordLateReply(result) }
        let submission = pump.submit(
            Win32NativeSmokeCommand(
                windowKey: key, requestID: NativeWindowRequestID(), ordinal: 0, provider: provider,
                observation: shared.observation, reply: reply))
        if submission != .rejected(.ownerStopped) {
            shared.fail(NativeOwnedSmokeFailure("late-command-was-not-rejected-by-stopped-owner"))
        }
    }
}
