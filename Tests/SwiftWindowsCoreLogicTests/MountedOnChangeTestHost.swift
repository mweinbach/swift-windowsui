import SwiftWindowsCore

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// An in-memory retained host. Plain model changes require an explicit reload;
/// mounted State writes use the coordinator's normal invalidation path.
@MainActor
final class MountedOnChangeTestHost {
    let runtime: RetainedViewRuntime
    let componentHost: ComponentHost
    let coordinator: StateMountCoordinator
    private(set) var isClosed = false

    init(
        size: Size = Size(width: 400, height: 300),
        content: @escaping @MainActor () -> AnyView
    ) {
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: size.width, height: size.height)))
        let componentHost = ComponentHost(runtime: runtime)
        let coordinator = StateMountCoordinator(
            invalidate: { [weak componentHost] in componentHost?.reload() },
            observeObject: { _ in },
            updateObservedObjects: { _, _, _ in })
        self.runtime = runtime
        self.componentHost = componentHost
        self.coordinator = coordinator
        componentHost.buildLifecycle = coordinator
        componentHost.shouldUpdate = { [weak self] in self?.isClosed == false }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator,
            canvasSizeProvider: { size },
            invalidateHandler: { [weak componentHost] in componentHost?.reload() })
        componentHost.setComponents { [weak self] in
            guard self?.isClosed == false else { return [] }
            return [makeViewComponent(content(), context: context)]
        }
    }

    func reload() {
        guard !isClosed else { return }
        componentHost.reload()
    }

    func render() {
        guard !isClosed else { return }
        _ = runtime.renderScene()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        runtime.stopRenderLifecycleCallbacks()
        coordinator.close()
        componentHost.onReloadCompleted = nil
        componentHost.setComponents { [] }
        // Revoke State before cancellation can reenter, and cancel while all
        // retained nodes are still reachable from this runtime's root.
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}
