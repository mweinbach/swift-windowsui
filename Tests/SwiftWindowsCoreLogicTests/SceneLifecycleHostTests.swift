import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The startup and mutation cases use the real batch host without ever
/// rendering a frame first. Only the explicit switching and snapshotter
/// cases exercise both render paths, after checking scene-driven appearance.
@MainActor
final class SceneLifecycleHostTests: XCTestCase {
    func testBatchStartupAppearsOnceAndConditionalRemovalDisappears() async throws {
        try await withTextLayout {
            let probe = SceneLifecycleProbe()
            let harness = SceneLifecycleHarness(SceneLifecycleConditionalRoot(probe: probe))
            defer { harness.close() }
            XCTAssertTrue(probe.events.isEmpty, "Building an unpresented host must not synthesize appearance")

            harness.start()
            await harness.settle()

            XCTAssertEqual(probe.events, [.appear("child"), .appear("survivor")])
            XCTAssertFalse(harness.batch.renderedScenes.isEmpty)
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty, "Startup must exercise the scene backend alone")
            let survivor = try harness.node("lifecycle.survivor")
            let visibility = try XCTUnwrap(probe.visibility)
            await harness.settle()
            XCTAssertEqual(probe.events, [.appear("child"), .appear("survivor")])

            visibility.wrappedValue = false
            await harness.settle()

            XCTAssertEqual(probe.events, [.appear("child"), .appear("survivor"), .disappear("child")])
            XCTAssertFalse(harness.contains("lifecycle.child"))
            XCTAssertTrue(try harness.node("lifecycle.survivor") === survivor)
            visibility.wrappedValue = true
            await harness.settle()
            XCTAssertEqual(
                probe.events,
                [.appear("child"), .appear("survivor"), .disappear("child"), .appear("child")])
            XCTAssertTrue(try harness.node("lifecycle.survivor") === survivor)
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
        }
    }

    func testAppearanceStateMutationsSurvivePaintingAndReachTheSubmittedScene() async throws {
        try await withTextLayout {
            let probe = SceneLifecycleProbe()
            let harness = SceneLifecycleHarness(SceneLifecycleMutatingRoot(probe: probe))
            defer { harness.close() }

            harness.start()
            await harness.settle()

            XCTAssertEqual(probe.events, [.appear("trigger"), .appear("followup")])
            XCTAssertEqual(try XCTUnwrap(probe.phase).wrappedValue, 2)
            XCTAssertTrue(probe.bodyPhases.contains(1), "The first appearance must rebuild mounted State")
            XCTAssertEqual(probe.bodyPhases.last, 2)
            XCTAssertEqual(try harness.node("lifecycle.phase").text, "Phase 2")
            let scene = try XCTUnwrap(harness.batch.renderedScenes.last)
            let markers = scene.layers.flatMap(\.quads).filter {
                abs($0.width - 24) < 0.001 && abs($0.height - 18) < 0.001
            }
            XCTAssertEqual(markers.count, 1)
            let marker = try XCTUnwrap(markers.first)
            XCTAssertEqual(marker.startR, 0.1, accuracy: 0.0001)
            XCTAssertEqual(marker.startG, 0.8, accuracy: 0.0001)
            XCTAssertEqual(marker.startB, 0.25, accuracy: 0.0001)
            XCTAssertFalse(harness.runtime.isDirty, "The callback's invalidation must eventually settle")
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)

            await harness.settle()

            XCTAssertEqual(probe.events, [.appear("trigger"), .appear("followup")])
            XCTAssertEqual(try harness.node("lifecycle.phase").text, "Phase 2")
        }
    }

    func testSceneCacheHitsAndFrameSceneSwitchingDoNotRepeatAppearance() async throws {
        try await withTextLayout {
            let probe = SceneLifecycleProbe()
            let harness = SceneLifecycleHarness(SceneLifecycleLeaf(identifier: "stable", probe: probe))
            defer { harness.close() }
            harness.start()
            await harness.settle()
            XCTAssertEqual(probe.events, [.appear("stable")])
            XCTAssertFalse(harness.batch.renderedScenes.isEmpty)
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
            let hitsBefore = harness.runtime.sceneCacheHitCount

            _ = harness.runtime.renderScene(at: harness.clock.now)
            _ = harness.runtime.renderScene(at: harness.clock.now)

            XCTAssertGreaterThanOrEqual(harness.runtime.sceneCacheHitCount, hitsBefore + 2)
            XCTAssertEqual(probe.events, [.appear("stable")])
            // Appearance has already been proved through the batch backend.
            // Switching runtime representations must share the same lifetime.
            for _ in 0..<3 {
                harness.clock.now += 0.05
                _ = harness.runtime.renderFrame(at: harness.clock.now)
                harness.clock.now += 0.05
                _ = harness.runtime.renderScene(at: harness.clock.now)
            }
            await harness.settle()

            XCTAssertEqual(probe.events, [.appear("stable")])
        }
    }

    func testAppearanceRemovingAPendingSiblingDoesNotDeliverItsStaleCallbacks() async throws {
        try await withTextLayout {
            let probe = SceneLifecycleProbe()
            let harness = SceneLifecycleHarness(SceneLifecycleRemovingRoot(probe: probe))
            defer { harness.close() }
            let initialPending = try harness.node("lifecycle.pending")

            harness.start()
            await harness.settle()

            XCTAssertEqual(probe.events, [.appear("remover")])
            XCTAssertFalse(harness.contains("lifecycle.pending"))
            XCTAssertNil(harness.runtime.resolvedLayoutFrame(of: initialPending))
            XCTAssertFalse(harness.runtime.isDirty)
            initialPending.opacity = 0.5
            XCTAssertFalse(harness.runtime.isDirty, "A removed node must not invalidate its former runtime")
            XCTAssertFalse(try XCTUnwrap(probe.visibility).wrappedValue)
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
            // The removed candidate never delivered an appearance, so it
            // must not synthesize a paired disappearance or suppress a later
            // fresh occurrence's legitimate callbacks.
            try XCTUnwrap(probe.visibility).wrappedValue = true
            await harness.settle()
            XCTAssertFalse(try harness.node("lifecycle.pending") === initialPending)
            XCTAssertEqual(probe.events, [.appear("remover"), .appear("pending")])
            try XCTUnwrap(probe.visibility).wrappedValue = false
            await harness.settle()
            XCTAssertEqual(probe.events, [.appear("remover"), .appear("pending"), .disappear("pending")])
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
        }
    }

    func testAppearanceClosingHostStopsLaterCallbacksAndBackendSubmission() async throws {
        try await withTextLayout {
            let probe = SceneLifecycleProbe()
            let harness = SceneLifecycleHarness(
                VStack {
                    SceneLifecycleLeaf(identifier: "closer", probe: probe)
                    SceneLifecycleLeaf(identifier: "pending", probe: probe)
                })
            defer { harness.close() }
            probe.onAppearance = { [weak host = harness.host, weak window = harness.window] identifier in
                guard identifier == "closer", let host, let window else { return }
                host.windowWillClose(window)
            }
            harness.host.onWindowClosed = { [weak probe] _ in probe?.closeCount += 1 }
            defer {
                probe.onAppearance = nil
                harness.host.onWindowClosed = nil
            }

            harness.start()
            await harness.settle()

            XCTAssertEqual(probe.events, [.appear("closer")])
            XCTAssertEqual(probe.closeCount, 1)
            XCTAssertTrue(harness.batch.boundScenes.isEmpty, "Close must abort before scene resource binding")
            XCTAssertTrue(harness.batch.renderedScenes.isEmpty, "A closed host must not submit the scene")
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
            XCTAssertNil(harness.window.nativeHandle)
            harness.close()
            await harness.settle()
            XCTAssertEqual(probe.events, [.appear("closer")])
            XCTAssertEqual(probe.closeCount, 1)
        }
    }

    func testSnapshotterSceneAndFrameShareOneAppearanceDelivery() async throws {
        try await withTextLayout {
            let probe = SceneLifecycleProbe()

            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: SceneLifecycleLeaf(identifier: "snapshot", probe: probe),
                size: IntSize(width: 240, height: 100), timestamp: 5_000)

            // Snapshotter intentionally produces a scene followed by a frame.
            // The real-host tests above establish scene-only startup; this
            // witness protects the public snapshot path against double delivery.
            XCTAssertEqual(probe.events, [.appear("snapshot")])
            XCTAssertFalse(snapshot.scene.layers.isEmpty)
            XCTAssertFalse(snapshot.frame.commands.isEmpty)
            _ = snapshot.runtime.renderScene(at: 5_001)
            _ = snapshot.runtime.renderFrame(at: 5_002)
            XCTAssertEqual(probe.events, [.appear("snapshot")])
        }
    }

    func testBatchSceneStartsTaskOnceAndRemovalCancelsBeforeRemount() async throws {
        try await withTextLayout {
            let probe = SceneLifecycleProbe()
            let work = SceneLifecycleTaskProbe()
            let harness = SceneLifecycleHarness(SceneLifecycleTaskRoot(probe: probe, work: work))
            defer {
                harness.close()
                work.releaseSuspensions()
            }
            XCTAssertTrue(work.starts.isEmpty)

            harness.start()
            await harness.settle()
            await work.waitFor(starts: 1)

            XCTAssertEqual(work.starts, [0])
            XCTAssertTrue(work.cancellations.isEmpty)
            XCTAssertTrue(work.completions.isEmpty, "The task must still be suspended while its view is present")
            XCTAssertEqual(probe.events, [.appear("task")])
            XCTAssertFalse(harness.batch.renderedScenes.isEmpty)
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
            await harness.settle()
            XCTAssertEqual(work.starts, [0], "Scene cache hits must not launch another task")
            let visibility = try XCTUnwrap(probe.visibility)

            visibility.wrappedValue = false
            await harness.settle()
            await work.waitFor(starts: 1, cancellations: 1, completions: 1)

            XCTAssertEqual(work.starts, [0])
            XCTAssertEqual(work.cancellations, [0])
            XCTAssertEqual(work.completions, [0])
            XCTAssertEqual(probe.events, [.appear("task"), .disappear("task")])
            XCTAssertFalse(harness.contains("lifecycle.task"))
            await harness.settle()
            XCTAssertEqual(work.starts, [0])

            visibility.wrappedValue = true
            await harness.settle()
            await work.waitFor(starts: 2, cancellations: 1, completions: 1)

            XCTAssertEqual(work.starts, [0, 1])
            XCTAssertEqual(work.cancellations, [0])
            XCTAssertEqual(work.completions, [0])
            XCTAssertEqual(probe.events, [.appear("task"), .disappear("task"), .appear("task")])
            visibility.wrappedValue = false
            await harness.settle()
            await work.waitFor(starts: 2, cancellations: 2, completions: 2)
            XCTAssertEqual(work.starts, [0, 1])
            XCTAssertEqual(work.cancellations, [0, 1])
            XCTAssertEqual(work.completions, [0, 1])
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
        }
    }

    func testAppearancePhaseChangeStartsOnlyTheLatestTaskOnTheSameTextNode() async throws {
        try await withTextLayout {
            let probe = SceneLifecycleProbe()
            let work = SceneLifecycleTaskProbe()
            let harness = SceneLifecycleHarness(SceneLifecycleVersionedTaskRoot(probe: probe, work: work))
            defer {
                harness.close()
                work.releaseSuspensions()
            }
            let original = try harness.node("lifecycle.versioned-task")

            harness.start()
            await harness.settle()
            await work.waitFor(starts: 1, suspended: 1)

            XCTAssertEqual(try XCTUnwrap(probe.phase).wrappedValue, 1)
            XCTAssertTrue(try harness.node("lifecycle.versioned-task") === original)
            XCTAssertEqual(original.text, "Task phase 1")
            XCTAssertEqual(probe.events, [.appear("versioned-task")])
            XCTAssertEqual(work.starts, [0])
            XCTAssertEqual(work.versions, [1], "The superseded phase-0 task must not launch after appearance rebuilds")
            XCTAssertEqual(work.suspendedCount, 1)
            XCTAssertTrue(work.cancellations.isEmpty)
            XCTAssertTrue(work.completions.isEmpty)
            XCTAssertFalse(harness.batch.renderedScenes.isEmpty)
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
            await harness.settle()
            XCTAssertEqual(work.starts, [0])
            XCTAssertEqual(work.versions, [1])
        }
    }

    func testExplicitCloseCancelsTaskAfterRevocationAndPreservesNormalFocusExit() async throws {
        try await withTextLayout {
            let lifetime = SceneLifecycleOwnerProbe()
            let work = SceneLifecycleTaskProbe()
            let harness = SceneLifecycleHarness(SceneLifecycleOwnerRoot(lifetime: lifetime, work: work))
            defer {
                harness.close()
                work.onSynchronousCancellation = nil
                work.releaseSuspensions()
            }
            harness.start()
            await harness.settle()
            await work.waitFor(starts: 1, suspended: 1)
            let editor = try harness.node("lifecycle.owned-editor")
            harness.runtime.requestFocus(editor)
            harness.host.window(harness.window, didInputText: "b")
            await harness.settle()
            let escaped = try XCTUnwrap(lifetime.value)
            let manager = try XCTUnwrap(lifetime.manager)
            XCTAssertEqual(work.starts, [0])
            XCTAssertEqual(work.suspendedCount, 1, "The cancellation handler must be installed before close")
            XCTAssertTrue(work.completions.isEmpty)
            XCTAssertEqual(lifetime.text, "ab")
            XCTAssertEqual(lifetime.editingEvents, [true])
            XCTAssertTrue(manager.canUndo)
            work.onSynchronousCancellation = { [weak lifetime, weak manager, weak editor, weak work] identifier in
                guard identifier == 0 else { return }
                guard let lifetime, let manager, let editor, let work else {
                    return XCTFail("Cancellation lost its live witness")
                }
                XCTAssertTrue(lifetime.isTerminating, "This check must run synchronously inside close")
                escaped.wrappedValue = 99
                manager.undo()
                lifetime.taskLaunchAttempts += 1
                editor.launchLifecycleTask(
                    ViewLifecycleTaskLaunch(
                        key: "closed-owner-cancellation-relaunch", priority: .userInitiated,
                        action: { [weak work] in await work?.run(version: 99) }))
                lifetime.cancellationSnapshots.append(
                    SceneLifecycleCancellationSnapshot(value: escaped.wrappedValue, text: lifetime.text))
            }
            harness.host.onWindowClosed = { [weak lifetime] _ in lifetime?.closeCount += 1 }
            lifetime.isTerminating = true

            harness.close()

            lifetime.isTerminating = false
            XCTAssertEqual(work.synchronousCancellations, [0])
            XCTAssertEqual(lifetime.taskLaunchAttempts, 1)
            XCTAssertEqual(lifetime.cancellationSnapshots, [.init(value: 7, text: "ab")])
            XCTAssertEqual(lifetime.editingEvents, [true, false])
            XCTAssertEqual(lifetime.closeCount, 1)
            XCTAssertEqual(escaped.wrappedValue, 7)
            XCTAssertEqual(lifetime.textWrites, ["ab"])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            await work.waitFor(starts: 1, cancellations: 1, completions: 1)
            await harness.settle()
            XCTAssertEqual(work.starts, [0], "Cancellation must not launch a new task on the closed editor")
            XCTAssertTrue(work.versions.isEmpty)
            XCTAssertEqual(work.suspendedCount, 0)
            XCTAssertEqual(work.cancellations, [0])
            XCTAssertEqual(work.completions, [0])
            XCTAssertTrue(harness.frame.renderedFrames.isEmpty)
        }
    }

    func testDroppingHostCancelsTaskAfterRevocationWithoutWindowLifecycleCallbacks() async throws {
        try await withTextLayout {
            let lifetime = SceneLifecycleOwnerProbe()
            let work = SceneLifecycleTaskProbe()
            let clock = RuntimeTestClock()
            clock.now = 5_000
            let frame = FakeRenderBackend()
            let batch = FakeBatchRenderBackend()
            let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 400, height: 300), scaleFactor: 1)
            let window = Win32Window(title: "Released scene task owner", clientSize: surface.pixelSize)
            window.testMonitorRefreshRateOverride = 60
            window.testScaleFactorOverride = 1
            var host: WinSwiftUIWindowHost? = WinSwiftUIWindowHost(
                configuration: WindowGroupConfiguration(
                    title: "Released scene task owner", size: surface.pixelSize, clearColor: .black,
                    content: [AnyView(SceneLifecycleOwnerRoot(lifetime: lifetime, work: work))]),
                platformWindow: window, renderer: frame, batchRenderer: batch,
                surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
            defer {
                host = nil
                work.onSynchronousCancellation = nil
                work.releaseSuspensions()
            }
            host?.frameClock = { clock.now }
            host?.hostedRuntime.clock = { clock.now }
            host?.windowDidCreate(window)
            await work.waitFor(starts: 1, suspended: 1)
            let runtime = try XCTUnwrap(host?.hostedRuntime)
            let editor = try XCTUnwrap(
                sceneLifecycleNodes(in: runtime.root).first { $0.accessibilityIdentifier == "lifecycle.owned-editor" })
            runtime.requestFocus(editor)
            host?.window(window, didInputText: "b")
            clock.now += 0.05
            host?.windowNeedsDisplay(window)
            let escaped = try XCTUnwrap(lifetime.value)
            let manager = try XCTUnwrap(lifetime.manager)
            XCTAssertEqual(work.starts, [0])
            XCTAssertEqual(work.suspendedCount, 1, "The cancellation handler must be installed before host release")
            XCTAssertTrue(work.completions.isEmpty)
            XCTAssertEqual(lifetime.appearCount, 1)
            XCTAssertEqual(lifetime.editingEvents, [true])
            XCTAssertEqual(lifetime.text, "ab")
            XCTAssertTrue(manager.canUndo)
            XCTAssertFalse(batch.renderedScenes.isEmpty)
            XCTAssertTrue(frame.renderedFrames.isEmpty)
            work.onSynchronousCancellation = { [weak lifetime, weak manager, weak editor, weak work] identifier in
                guard identifier == 0 else { return }
                guard let lifetime, let manager, let editor, let work else {
                    return XCTFail("Cancellation lost its live witness")
                }
                XCTAssertTrue(lifetime.isTerminating, "This check must run synchronously inside host release")
                escaped.wrappedValue = 99
                manager.undo()
                lifetime.taskLaunchAttempts += 1
                editor.launchLifecycleTask(
                    ViewLifecycleTaskLaunch(
                        key: "closed-owner-cancellation-relaunch", priority: .userInitiated,
                        action: { [weak work] in await work?.run(version: 99) }))
                lifetime.cancellationSnapshots.append(
                    SceneLifecycleCancellationSnapshot(value: escaped.wrappedValue, text: lifetime.text))
            }
            host?.onWindowClosed = { [weak lifetime] _ in lifetime?.closeCount += 1 }
            weak var releasedHost = host
            lifetime.isTerminating = true

            host = nil

            lifetime.isTerminating = false
            XCTAssertNil(releasedHost, "A suspended task and retained runtime must not own their host")
            XCTAssertEqual(work.synchronousCancellations, [0])
            XCTAssertEqual(lifetime.taskLaunchAttempts, 1)
            XCTAssertEqual(lifetime.cancellationSnapshots, [.init(value: 7, text: "ab")])
            XCTAssertEqual(lifetime.editingEvents, [true])
            XCTAssertEqual(lifetime.disappearCount, 0)
            XCTAssertEqual(lifetime.closeCount, 0)
            XCTAssertEqual(escaped.wrappedValue, 7)
            XCTAssertEqual(lifetime.textWrites, ["ab"])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            await work.waitFor(starts: 1, cancellations: 1, completions: 1)
            for _ in 0..<4 { await Task.yield() }
            XCTAssertEqual(work.starts, [0], "Cancellation must not launch a new task on the orphaned editor")
            XCTAssertTrue(work.versions.isEmpty)
            XCTAssertEqual(work.suspendedCount, 0)
            XCTAssertEqual(work.cancellations, [0])
            XCTAssertEqual(work.completions, [0])
            XCTAssertEqual(lifetime.editingEvents, [true])
            XCTAssertEqual(lifetime.disappearCount, 0)
            XCTAssertEqual(lifetime.closeCount, 0)
            XCTAssertNil(window.nativeHandle)
            withExtendedLifetime((runtime, escaped, manager, window)) {}
        }
    }

    private func withTextLayout(_ body: @MainActor () async throws -> Void) async throws {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = Array(text).enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                    glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                    fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let size = Size(width: Double(max(text.count, 1)) * 9, height: max(style.nativeFontPixelSize, 1))
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        try await body()
    }
}

private enum SceneLifecycleEvent: Equatable {
    case appear(String)
    case disappear(String)
}

@MainActor
private final class SceneLifecycleProbe {
    var events: [SceneLifecycleEvent] = []
    var visibility: Binding<Bool>?
    var phase: Binding<Int>?
    var bodyPhases: [Int] = []
    var closeCount = 0
    var onAppearance: (@MainActor (String) -> Void)?

    func appear(_ identifier: String) {
        events.append(.appear(identifier))
        onAppearance?(identifier)
    }

    func disappear(_ identifier: String) { events.append(.disappear(identifier)) }
}

@MainActor
private final class SceneLifecycleTaskProbe {
    private(set) var starts: [Int] = []
    private(set) var versions: [Int] = []
    private(set) var cancellations: [Int] = []
    private(set) var synchronousCancellations: [Int] = []
    private(set) var completions: [Int] = []
    var onSynchronousCancellation: (@MainActor (Int) -> Void)?
    private var suspended: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isFinishing = false

    var suspendedCount: Int { suspended.count }

    func run(version: Int? = nil) async {
        let identifier = starts.count
        starts.append(identifier)
        if let version { versions.append(version) }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || cancellations.contains(identifier) {
                    recordCancellation(identifier)
                    continuation.resume()
                } else if isFinishing {
                    continuation.resume()
                } else {
                    suspended[identifier] = continuation
                }
            }
        } onCancel: {
            // These fixtures cancel an already suspended task only through
            // main-actor view removal, host close, or isolated host deinit.
            // Run the witness inline: queueing it would hide bad revocation
            // order by allowing close to finish before its State/undo writes.
            MainActor.assumeIsolated { [weak self] in
                self?.synchronousCancellations.append(identifier)
                self?.onSynchronousCancellation?(identifier)
            }
            Task { @MainActor [weak self] in self?.recordCancellation(identifier) }
        }
        completions.append(identifier)
    }

    private func recordCancellation(_ identifier: Int) {
        if !cancellations.contains(identifier) { cancellations.append(identifier) }
        suspended.removeValue(forKey: identifier)?.resume()
    }

    func waitFor(starts: Int, cancellations: Int = 0, completions: Int = 0, suspended: Int = 0) async {
        // Bounded executor yields leave a missing launch/cancellation as an
        // assertion failure, not a hung continuation or a time-based sleep.
        for _ in 0..<64 {
            if self.starts.count >= starts && self.cancellations.count >= cancellations
                && self.completions.count >= completions && self.suspended.count >= suspended
            {
                return
            }
            await Task.yield()
        }
    }

    func releaseSuspensions() {
        isFinishing = true
        let continuations = Array(suspended.values)
        suspended.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

@MainActor
private struct SceneLifecycleLeaf: View {
    let identifier: String
    let probe: SceneLifecycleProbe

    var body: some View {
        Text(identifier)
            .accessibilityIdentifier("lifecycle.\(identifier)")
            .onAppear { probe.appear(identifier) }
            .onDisappear { probe.disappear(identifier) }
    }
}

@MainActor
private struct SceneLifecycleConditionalRoot: View {
    @State private var showsChild = true
    let probe: SceneLifecycleProbe

    var body: some View {
        probe.visibility = $showsChild
        return VStack(alignment: .leading, spacing: 8) {
            if showsChild { SceneLifecycleLeaf(identifier: "child", probe: probe) }
            SceneLifecycleLeaf(identifier: "survivor", probe: probe)
        }
    }
}

@MainActor
private struct SceneLifecycleMutatingRoot: View {
    @State private var phase = 0
    let probe: SceneLifecycleProbe

    var body: some View {
        probe.phase = $phase
        probe.bodyPhases.append(phase)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Phase \(phase)").accessibilityIdentifier("lifecycle.phase")
            Rectangle()
                .fill(
                    phase == 2
                        ? Color(red: 0.1, green: 0.8, blue: 0.25)
                        : Color(red: 0.85, green: 0.15, blue: 0.2)
                )
                .frame(width: 24, height: 18)
            Text("Trigger")
                .onAppear {
                    probe.appear("trigger")
                    phase = 1
                }
            if phase > 0 {
                Text("Followup")
                    .onAppear {
                        probe.appear("followup")
                        phase = 2
                    }
            }
        }
    }
}

@MainActor
private struct SceneLifecycleRemovingRoot: View {
    @State private var showsPending = true
    let probe: SceneLifecycleProbe

    var body: some View {
        probe.visibility = $showsPending
        return VStack(alignment: .leading, spacing: 8) {
            Text("Remover")
                .accessibilityIdentifier("lifecycle.remover")
                .onAppear {
                    probe.appear("remover")
                    showsPending = false
                }
            if showsPending { SceneLifecycleLeaf(identifier: "pending", probe: probe) }
        }
    }
}

@MainActor
private struct SceneLifecycleTaskRoot: View {
    @State private var showsTask = true
    let probe: SceneLifecycleProbe
    let work: SceneLifecycleTaskProbe

    var body: some View {
        probe.visibility = $showsTask
        return VStack(alignment: .leading, spacing: 8) {
            if showsTask {
                SceneLifecycleLeaf(identifier: "task", probe: probe)
                    .task { await work.run() }
            }
            Text("Task owner")
        }
    }
}

@MainActor
private struct SceneLifecycleVersionedTaskRoot: View {
    @State private var phase = 0
    let probe: SceneLifecycleProbe
    let work: SceneLifecycleTaskProbe

    var body: some View {
        let version = phase
        probe.phase = $phase
        return Text("Task phase \(phase)")
            .accessibilityIdentifier("lifecycle.versioned-task")
            .onAppear {
                probe.appear("versioned-task")
                phase = 1
            }
            .task(id: version) { await work.run(version: version) }
    }
}

private struct SceneLifecycleCancellationSnapshot: Equatable {
    let value: Int
    let text: String
}

@MainActor
private final class SceneLifecycleOwnerProbe {
    var value: Binding<Int>?
    var text = "a"
    var textWrites: [String] = []
    var editingEvents: [Bool] = []
    weak var manager: WinSwiftUI.UndoManager?
    var appearCount = 0
    var disappearCount = 0
    var closeCount = 0
    var isTerminating = false
    var taskLaunchAttempts = 0
    var cancellationSnapshots: [SceneLifecycleCancellationSnapshot] = []
}

@MainActor
private struct SceneLifecycleOwnerRoot: View {
    @State private var value = 7
    let lifetime: SceneLifecycleOwnerProbe
    let work: SceneLifecycleTaskProbe

    var body: some View {
        lifetime.value = $value
        return VStack(alignment: .leading, spacing: 8) {
            SceneLifecycleOwnedField(lifetime: lifetime)
            Text("Task owner \(value)")
                .onAppear { lifetime.appearCount += 1 }
                .onDisappear { lifetime.disappearCount += 1 }
                .task { await work.run() }
        }
    }
}

@MainActor
private struct SceneLifecycleOwnedField: View {
    @Environment(\.undoManager) private var manager
    let lifetime: SceneLifecycleOwnerProbe

    var body: some View {
        lifetime.manager = manager
        // Unlike mounted State, this reference-model Binding cannot defend
        // itself after its owner closes. The editor session must be revoked.
        let text = Binding<String>(
            get: { lifetime.text },
            set: {
                lifetime.textWrites.append($0)
                lifetime.text = $0
            })
        return TextField("Text", text: text, onEditingChanged: { lifetime.editingEvents.append($0) })
            .accessibilityIdentifier("lifecycle.owned-editor")
            .frame(width: 320, height: 44)
    }
}

@MainActor
private func sceneLifecycleNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private final class SceneLifecycleHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let frame: FakeRenderBackend
    let batch: FakeBatchRenderBackend
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init<Content: View>(_ content: Content) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let frame = FakeRenderBackend()
        let batch = FakeBatchRenderBackend()
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 400, height: 300), scaleFactor: 1)
        let window = Win32Window(title: "Scene lifecycle", clientSize: surface.pixelSize)
        window.testMonitorRefreshRateOverride = 60
        window.testScaleFactorOverride = 1
        self.clock = clock
        self.frame = frame
        self.batch = batch
        self.window = window
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Scene lifecycle", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window, renderer: frame, batchRenderer: batch,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
    }

    func start() { host.windowDidCreate(window) }

    func settle() async {
        for _ in 0..<4 {
            clock.now += 0.05
            host.windowNeedsDisplay(window)
            await Task.yield()
        }
    }

    func close() { host.windowWillClose(window) }

    func contains(_ identifier: String) -> Bool {
        sceneLifecycleNodes(in: runtime.root).contains { $0.accessibilityIdentifier == identifier }
    }

    func node(_ identifier: String) throws -> ViewNode {
        try XCTUnwrap(sceneLifecycleNodes(in: runtime.root).first { $0.accessibilityIdentifier == identifier })
    }
}
