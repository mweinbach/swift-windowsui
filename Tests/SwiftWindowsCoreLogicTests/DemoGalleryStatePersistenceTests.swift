import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Gallery interactions must survive the real host rebuilding its SwiftUI view
/// values. Keeping these bindings in nested `@State` silently reset every
/// editor and dismissed sheets as soon as the observed app model changed.
@MainActor
final class DemoGalleryStatePersistenceTests: XCTestCase {
    private func makeHost(model: DemoDashboardModel) -> (WinSwiftUIWindowHost, Win32Window) {
        let size = IntSize(width: 1280, height: 720)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: size,
            scaleFactor: 1
        )
        let configuration = WindowGroupConfiguration(
            title: "Gallery persistence",
            size: size,
            clearColor: .black,
            content: [AnyView(DemoRootView(model: model))]
        )
        let host = WinSwiftUIWindowHost(
            configuration: configuration,
            renderer: FakeRenderBackend(),
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }
        )
        let window = Win32Window(title: "Gallery persistence", clientSize: size)
        host.windowDidCreate(window)
        return (host, window)
    }

    private func firstNode(in root: ViewNode, matching predicate: (ViewNode) -> Bool) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if predicate(node) {
                return node
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    private func activatingNode(in root: ViewNode, label: String) -> ViewNode? {
        if let labeled = firstNode(
            in: root,
            matching: {
                $0.accessibilityLabel == label && $0.onActivate != nil
            })
        {
            return labeled
        }

        var candidate = firstNode(in: root, matching: { $0.text == label })
        while let node = candidate {
            if node.onActivate != nil {
                return node
            }
            candidate = node.parent
        }
        return nil
    }

    private func awaitHostReload(
        _ host: WinSwiftUIWindowHost,
        performing action: @MainActor () -> Void
    ) async {
        let reloaded = expectation(description: "observed gallery state rebuilt the real window host")
        host.onReloadContentCompleted = {
            reloaded.fulfill()
        }
        action()
        await fulfillment(of: [reloaded], timeout: 5)
        host.onReloadContentCompleted = nil
    }

    func testEveryControlRenderingAndPresentationStateHasADeterministicDefault() async {
        let state = DemoDashboardModel().galleryState

        XCTAssertEqual(state.draftName, "Native component kit")
        XCTAssertEqual(state.density, .balanced)
        XCTAssertTrue(state.liveUpdatesEnabled)
        XCTAssertFalse(state.notificationsEnabled)
        XCTAssertEqual(state.intensity, 0.62, accuracy: 0.0001)
        XCTAssertEqual(state.concurrency, 3)
        XCTAssertFalse(state.inspectorExpanded)
        XCTAssertFalse(state.colorsAreReversed)
        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.isSheetPresented)
        XCTAssertFalse(state.isPopoverPresented)
        XCTAssertFalse(state.isAlertPresented)
        XCTAssertFalse(state.isConfirmationPresented)
        XCTAssertFalse(state.areInteractionDetailsExpanded)
        XCTAssertTrue(state.isLivePreviewEnabled)
        XCTAssertFalse(state.areAlignmentGuidesEnabled)
    }

    func testGalleryStateHasStableIdentityAndPublishesItsOwnMutations() async {
        let model = DemoDashboardModel()
        let original = model.galleryState
        var notificationCount = 0
        let observation = original.objectWillChange.sink { _ in
            notificationCount += 1
        }

        original.draftName = "Persistent collection"
        original.notificationsEnabled = true
        original.colorsAreReversed = true
        _ = DemoRootView(model: model)
        _ = DemoRootView(model: model)

        XCTAssertTrue(original === model.galleryState)
        XCTAssertEqual(notificationCount, 3)
        XCTAssertEqual(model.galleryState.draftName, "Persistent collection")
        XCTAssertTrue(model.galleryState.notificationsEnabled)
        XCTAssertTrue(model.galleryState.colorsAreReversed)
        withExtendedLifetime(observation) {}
    }

    func testControlsAndRenderingStateSurviveFreshRootConstructionAndNavigation() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .gallery
        let state = model.galleryState
        state.draftName = "Reusable renderer catalog"
        state.density = .relaxed
        state.liveUpdatesEnabled = false
        state.notificationsEnabled = true
        state.intensity = 0.85
        state.concurrency = 7
        state.inspectorExpanded = true
        state.colorsAreReversed = true
        state.isExpanded = true
        state.areInteractionDetailsExpanded = true
        state.isLivePreviewEnabled = false
        state.areAlignmentGuidesEnabled = true

        let initial = WinSwiftUIRendererSnapshotter.snapshot(of: DemoRootView(model: model))
        XCTAssertNotNil(firstNode(in: initial.runtime.root, matching: { $0.text == "85%" }))
        XCTAssertNotNil(firstNode(in: initial.runtime.root, matching: { $0.text == "Expanded" }))

        model.selectedScreen = .settings
        _ = WinSwiftUIRendererSnapshotter.snapshot(of: DemoRootView(model: model))
        model.selectedScreen = .gallery
        let restored = WinSwiftUIRendererSnapshotter.snapshot(of: DemoRootView(model: model))

        XCTAssertTrue(state === model.galleryState)
        XCTAssertEqual(state.draftName, "Reusable renderer catalog")
        XCTAssertEqual(state.density, .relaxed)
        XCTAssertFalse(state.liveUpdatesEnabled)
        XCTAssertTrue(state.notificationsEnabled)
        XCTAssertEqual(state.intensity, 0.85, accuracy: 0.0001)
        XCTAssertEqual(state.concurrency, 7)
        XCTAssertTrue(state.inspectorExpanded)
        XCTAssertTrue(state.colorsAreReversed)
        XCTAssertTrue(state.isExpanded)
        XCTAssertTrue(state.areInteractionDetailsExpanded)
        XCTAssertFalse(state.isLivePreviewEnabled)
        XCTAssertTrue(state.areAlignmentGuidesEnabled)
        XCTAssertNotNil(firstNode(in: restored.runtime.root, matching: { $0.text == "85%" }))
        XCTAssertNotNil(firstNode(in: restored.runtime.root, matching: { $0.text == "Expanded" }))
    }

    func testPublishedEditorAndToggleMutationsRebuildTheRealWindowHostWithoutResetting() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .gallery
        let (host, _) = makeHost(model: model)
        let original = model.galleryState

        await awaitHostReload(host) {
            original.draftName = "Host-backed editor"
            original.notificationsEnabled = true
            original.intensity = 0.8
        }

        XCTAssertGreaterThanOrEqual(host.executedReloadCount, 1)
        XCTAssertTrue(original === model.galleryState)
        XCTAssertEqual(model.galleryState.draftName, "Host-backed editor")
        XCTAssertTrue(model.galleryState.notificationsEnabled)
        XCTAssertEqual(model.galleryState.intensity, 0.8, accuracy: 0.0001)
        XCTAssertNotNil(
            firstNode(in: host.hostedRuntime.root, matching: { $0.text == "80%" }),
            "the retained host must compose its follow-up tree from persisted slider state"
        )
        XCTAssertNotNil(
            firstNode(
                in: host.hostedRuntime.root,
                matching: {
                    $0.text == "\(original.draftName.count)/36"
                }),
            "the rebuilt host must derive validation from the current editor binding"
        )
    }

    func testActivatedSheetAndPopoverSurviveObservedHostAndRootReconstruction() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .gallery
        let (host, _) = makeHost(model: model)

        guard let openSheet = activatingNode(in: host.hostedRuntime.root, label: "Open Sheet") else {
            return XCTFail("the live gallery must expose an activatable sheet example")
        }

        await awaitHostReload(host) {
            openSheet.onActivate?()
        }

        XCTAssertTrue(model.galleryState.isSheetPresented)
        XCTAssertNotNil(firstNode(in: host.hostedRuntime.root, matching: { $0.text == "Configure presentation" }))

        let reconstructed = WinSwiftUIRendererSnapshotter.snapshot(of: DemoRootView(model: model))
        XCTAssertNotNil(
            firstNode(in: reconstructed.runtime.root, matching: { $0.text == "Configure presentation" }),
            "reconstructing the entire SwiftUI root must retain the live sheet binding"
        )

        await awaitHostReload(host) {
            model.galleryState.isSheetPresented = false
        }

        guard let openPopover = activatingNode(in: host.hostedRuntime.root, label: "Show Popover") else {
            return XCTFail("the live gallery must expose an activatable popover example")
        }

        await awaitHostReload(host) {
            openPopover.onActivate?()
        }

        XCTAssertTrue(model.galleryState.isPopoverPresented)
        XCTAssertNotNil(
            firstNode(in: host.hostedRuntime.root, matching: { $0.text == "Renderer details" }),
            "a real observed-object rebuild must retain and compose the anchored popover"
        )
    }
}
