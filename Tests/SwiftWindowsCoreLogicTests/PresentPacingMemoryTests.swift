import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// The launch-slideshow fix. The watchdog demands ~1.5 s of consecutive
// blocked presents before it takes the pacing job away from the display —
// right for a healthy machine, and a slideshow replayed at every launch on a
// machine that is broken every session. The store below remembers the verdict
// per adapter+display pair; the host seeds both presenters from it at attach
// and files every settled verdict back, so "drop the memory when a probe
// passes" is a property of the ordinary frame loop rather than a special
// case.

@MainActor
final class PresentPacingMemoryTests: XCTestCase {
    private var scratchURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pacing-memory-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("present-pacing.json", isDirectory: false)
    }

    override func tearDown() async throws {
        if let scratchURL {
            try? FileManager.default.removeItem(at: scratchURL.deletingLastPathComponent())
        }
        try await super.tearDown()
    }

    // MARK: - The store

    func testAVerdictSurvivesTheProcess() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)
        store.setRemembersSelfPacing(true, forKey: "adapter|display")

        // A second store on the same file is the next launch.
        let nextLaunch = PresentPacingMemoryStore(fileURL: scratchURL)
        XCTAssertTrue(
            nextLaunch.remembersSelfPacing(forKey: "adapter|display"),
            "A verdict that dies with the process buys the next launch nothing."
        )
        XCTAssertFalse(nextLaunch.remembersSelfPacing(forKey: "adapter|other-display"))
    }

    func testDroppingTheVerdictRemovesTheEntryAndEventuallyTheFile() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)
        store.setRemembersSelfPacing(true, forKey: "adapter|display")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratchURL.path))

        store.setRemembersSelfPacing(false, forKey: "adapter|display")

        XCTAssertFalse(PresentPacingMemoryStore(fileURL: scratchURL).remembersSelfPacing(forKey: "adapter|display"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: scratchURL.path),
            "A machine whose displays are all healthy converges on no file, not a file of reassurances."
        )
    }

    func testAHealthyMachineNeverCreatesTheFile() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)

        // The frame loop files `displayPaced` verdicts continuously on a
        // healthy machine; none of them may cost a disk write.
        store.setRemembersSelfPacing(false, forKey: "adapter|display")
        store.setRemembersSelfPacing(false, forKey: "adapter|display")

        XCTAssertFalse(FileManager.default.fileExists(atPath: scratchURL.path))
    }

    func testACorruptFileIsForgottenNotTrusted() async {
        try? FileManager.default.createDirectory(
            at: scratchURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("not json at all".utf8).write(to: scratchURL)

        let store = PresentPacingMemoryStore(fileURL: scratchURL)
        XCTAssertFalse(store.remembersSelfPacing(forKey: "adapter|display"))

        // And the store still works from there.
        store.setRemembersSelfPacing(true, forKey: "adapter|display")
        XCTAssertTrue(PresentPacingMemoryStore(fileURL: scratchURL).remembersSelfPacing(forKey: "adapter|display"))
    }

    func testKeysAreIndependent() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)
        store.setRemembersSelfPacing(true, forKey: "adapter|headless-virtual")
        store.setRemembersSelfPacing(true, forKey: "adapter|dock-monitor")
        store.setRemembersSelfPacing(false, forKey: "adapter|dock-monitor")

        XCTAssertTrue(store.remembersSelfPacing(forKey: "adapter|headless-virtual"))
        XCTAssertFalse(
            store.remembersSelfPacing(forKey: "adapter|dock-monitor"),
            "The dock monitor recovering must not erase what is known about the headless display."
        )
    }

    // MARK: - Host integration

    private static let surface = SurfaceDescriptor(
        windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
        pixelSize: IntSize(width: 320, height: 200),
        scaleFactor: 1.0
    )

    private func makeHost(
        batch: FakeBatchRenderBackend,
        frame: FakeRenderBackend = FakeRenderBackend(),
        store: PresentPacingMemoryStore,
        clock: FakeRecoveryClock,
        displayIdentity: String = "TEST-DISPLAY"
    ) -> (WinSwiftUIWindowHost, Win32Window) {
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            ),
            renderer: frame,
            batchRenderer: batch,
            surfaceDescriptorProvider: { _ in Self.surface },
            sceneRenderer: { runtime, timestamp in runtime.renderScene(at: timestamp) },
            startupProbeConfiguration: nil,
            presentPacingMemory: store
        )
        host.frameClock = { clock.now }
        host.platformWindow.testDisplayIdentityOverride = displayIdentity

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        window.testMonitorRefreshRateOverride = 60
        host.windowDidCreate(window)
        return (host, window)
    }

    /// The key the host files this fake configuration under: the fake batch
    /// backend reports no adapter diagnostics, so its display name stands in.
    private var expectedKey: String { "FAKE BATCH|TEST-DISPLAY" }

    func testARememberedVerdictSeedsBothPresentersAtAttach() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)
        store.setRemembersSelfPacing(true, forKey: expectedKey)

        let batch = FakeBatchRenderBackend()
        let frame = FakeRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        _ = makeHost(batch: batch, frame: frame, store: store, clock: clock)

        XCTAssertEqual(batch.adoptRememberedSelfPacingCallCount, 1)
        XCTAssertEqual(
            frame.adoptRememberedSelfPacingCallCount,
            1,
            "The frame fallback carries the same watchdog; a mid-session downgrade must not resurrect the slideshow."
        )
    }

    func testNoMemoryMeansNoSeeding() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)

        let batch = FakeBatchRenderBackend()
        let frame = FakeRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        _ = makeHost(batch: batch, frame: frame, store: store, clock: clock)

        XCTAssertEqual(batch.adoptRememberedSelfPacingCallCount, 0)
        XCTAssertEqual(frame.adoptRememberedSelfPacingCallCount, 0)
    }

    func testAnEngagedWatchdogWritesTheMemory() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let (host, window) = makeHost(batch: batch, store: store, clock: clock)

        // The backend's watchdog took the pacing job away mid-session.
        batch.presentPacing = PresentPacingStatus(
            mode: .selfPaced, displayFrameInterval: 1.0 / 60.0, engagementCount: 1)
        clock.now += 0.020
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)

        XCTAssertTrue(
            store.remembersSelfPacing(forKey: expectedKey),
            "The verdict must be on disk before the session ends, or the next launch re-earns it at 4 fps."
        )
    }

    func testAPassedProbeDropsTheMemory() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)
        store.setRemembersSelfPacing(true, forKey: expectedKey)

        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let (host, window) = makeHost(batch: batch, store: store, clock: clock)

        // The confirmation probe passed: the backend reports display pacing.
        batch.presentPacing = PresentPacingStatus(mode: .displayPaced, displayFrameInterval: 1.0 / 60.0)
        clock.now += 0.020
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)

        XCTAssertFalse(
            store.remembersSelfPacing(forKey: expectedKey),
            "A display that started behaving must not be remembered as broken into every future launch."
        )
    }

    func testAProbeInFlightFilesNoVerdict() async {
        let store = PresentPacingMemoryStore(fileURL: scratchURL)
        store.setRemembersSelfPacing(true, forKey: expectedKey)

        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let (host, window) = makeHost(batch: batch, store: store, clock: clock)

        batch.presentPacing = PresentPacingStatus(mode: .probingDisplay, displayFrameInterval: 1.0 / 60.0)
        clock.now += 0.020
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)

        XCTAssertTrue(
            store.remembersSelfPacing(forKey: expectedKey),
            "A probe says nothing yet; only settled modes are verdicts."
        )
    }
}
