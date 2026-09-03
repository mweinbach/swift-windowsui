import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Frozen before the storage correction. No fixture depth or stack limit is
/// changed; the original Frame77 metadata fixtures remain independent controls.
@MainActor
final class ModifiedViewContentStorageTests: XCTestCase {
    func testInlinePayloadSizeStaysBoundedAcrossThirtyTwoModifiers() async {
        let one = Text("Seed").opacity(1)
        let sixteen = one.opacity(1).opacity(1).opacity(1).opacity(1).opacity(1)
            .opacity(1).opacity(1).opacity(1).opacity(1).opacity(1)
            .opacity(1).opacity(1).opacity(1).opacity(1).opacity(1)
        let thirtyTwo = sixteen.opacity(1).opacity(1).opacity(1).opacity(1)
            .opacity(1).opacity(1).opacity(1).opacity(1).opacity(1).opacity(1)
            .opacity(1).opacity(1).opacity(1).opacity(1).opacity(1).opacity(1)

        XCTAssertGreaterThan(inlineSize(one), 0)
        XCTAssertEqual(inlineSize(sixteen), inlineSize(one))
        XCTAssertEqual(inlineSize(thirtyTwo), inlineSize(one))
        let runtime = RetainedViewRuntime(root: ViewNode())
        defer { storageClose(runtime) }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 180, height: 80) }, invalidateHandler: {})
        let node = thirtyTwo.makeComponent(context: context).makeNode(runtime: runtime)
        XCTAssertEqual(node.text, "Seed")
    }

    func testCopiesKeepOriginalContentAndIndependentOuterMetadata() async {
        var source = StorageValueLeaf(label: "Original")
        var first = ModifiedView(content: source) { content, context in content.makeComponent(context: context) }
        var second = first
        source.label = "Changed source"
        first.id = "first"
        first.explicitViewIdentity = RetainedViewIdentity.Key("first")
        first.selectionTag = AnyHashable("first tag")
        first.navigationTitle = [AnyView(Text("First title"))]
        second.id = "second"
        second.explicitViewIdentity = RetainedViewIdentity.Key("second")
        second.selectionTag = AnyHashable("second tag")

        XCTAssertEqual(first.content.label, "Original")
        XCTAssertEqual(second.content.label, "Original")
        XCTAssertEqual(source.label, "Changed source")
        XCTAssertEqual(first.id, "first")
        XCTAssertEqual(second.id, "second")
        XCTAssertEqual(first.anySelectionTag, AnyHashable("first tag"))
        XCTAssertEqual(second.anySelectionTag, AnyHashable("second tag"))
        XCTAssertEqual(first.anyNavigationTitle?.count, 1)
        XCTAssertNil(second.anyNavigationTitle)
        var extracted = first.content
        extracted.label = "Changed extracted copy"
        XCTAssertEqual(first.content.label, "Original")
        XCTAssertEqual(second.content.label, "Original")
    }

    func testMetadataIsReadAtOriginalErasurePointsBeforeTransform() async {
        let probe = StorageMetadataProbe()
        let source = StorageMetadataLeaf(probe: probe)
        let wrapped = ModifiedView(content: source) { _, _ in
            probe.events.append("transform")
            return Component { _ in ViewNode() }
        }
        XCTAssertTrue(probe.events.isEmpty)
        probe.tag = "Before first erasure"
        let erased = AnyView(wrapped)
        let metadataOrder = [
            "tag", "tab", "badge", "title", "subtitle", "displayMode", "backHidden", "barHidden",
            "toolbar", "destinations", "presented", "swipe",
        ]
        XCTAssertEqual(probe.events, metadataOrder)
        XCTAssertEqual(erased.selectionTag, AnyHashable("Before first erasure"))
        XCTAssertEqual(probe.bodyCalls, 0)
        XCTAssertEqual(probe.componentCalls, 0)
        probe.events.removeAll()
        probe.tag = "Before component construction"

        _ = wrapped.makeComponent(
            context: ViewBuildContext(
                canvasSizeProvider: { Size(width: 180, height: 80) }, invalidateHandler: {}))

        XCTAssertEqual(probe.events, metadataOrder + ["transform"])
        XCTAssertEqual(erased.selectionTag, AnyHashable("Before first erasure"))
        XCTAssertEqual(wrapped.anySelectionTag, AnyHashable("Before component construction"))
        XCTAssertEqual(probe.bodyCalls, 0)
        XCTAssertEqual(probe.componentCalls, 0)
    }

    func testDeclarationAndComponentIdentityKeepOriginalContentTypes() async {
        var observed: RetainedViewIdentity?
        var wrapped = ModifiedView(content: StorageValueLeaf(label: "Content")) { _, context in
            observed = context.retainedViewIdentity
            return Component { _ in ViewNode() }
        }
        let explicit = RetainedViewIdentity.Key("stable")
        wrapped.explicitViewIdentity = explicit
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 180, height: 80) }, invalidateHandler: {})
        let wrapperPath = RetainedViewIdentity(segments: [.view(ObjectIdentifier(type(of: wrapped)))])
        let explicitPath = wrapperPath.appending(.explicit(explicit))
        let contentPath = explicitPath.appending(contentsOf: [
            .role(.content), .view(ObjectIdentifier(StorageValueLeaf.self)),
        ])
        let declared = resolveDeclaredStateMountScopes(of: wrapped, context: context)

        XCTAssertEqual(declared.map(\.prefix), [wrapperPath, explicitPath, contentPath])
        XCTAssertNil(observed, "Declaration discovery must not invoke the transform")
        _ = wrapped.makeComponent(context: context)
        XCTAssertEqual(observed, contentPath)
    }

    func testContentCaptureSurvivesCopiesAndReleasesAfterLastValue() async {
        var releases = 0
        weak var original: StorageLifetimeProbe?
        @inline(never)
        func makeWrapped() -> ModifiedView<StorageLifetimeLeaf> {
            let probe = StorageLifetimeProbe { releases += 1 }
            original = probe
            return ModifiedView(content: StorageLifetimeLeaf(probe: probe)) { _, _ in
                Component { _ in ViewNode() }
            }
        }
        var first: ModifiedView<StorageLifetimeLeaf>? = makeWrapped()
        var second = first
        XCTAssertNotNil(original)
        XCTAssertEqual(releases, 0)
        first = nil
        XCTAssertNotNil(original)
        XCTAssertEqual(releases, 0)
        withExtendedLifetime(second) {}
        second = nil
        XCTAssertNil(original)
        XCTAssertEqual(releases, 1)
    }

    func testPrebuiltContentInstallsLocalStateSeparatelyInTwoOwners() async throws {
        let probe = StorageStateProbe()
        let source = StorageStateLeaf(probe: probe)
        let wrapped = source.disabled(true)
        XCTAssertTrue(probe.values.isEmpty)
        XCTAssertEqual(source.value, 5)
        let first = StorageStateHost { AnyView(wrapped) }
        defer { first.close() }
        let firstBinding = try XCTUnwrap(probe.bindings.last)
        let second = StorageStateHost { AnyView(wrapped) }
        defer { second.close() }
        let secondBinding = try XCTUnwrap(probe.bindings.last)
        XCTAssertEqual(probe.values, [5, 5])
        XCTAssertEqual(probe.enabled, [false, false])
        XCTAssertEqual(source.value, 5)

        firstBinding.wrappedValue = 9

        XCTAssertEqual(firstBinding.wrappedValue, 9)
        XCTAssertEqual(secondBinding.wrappedValue, 5)
        XCTAssertEqual(source.value, 5, "Installation must not write a mounted cell into shared original content")
        XCTAssertEqual(probe.values, [5, 5, 9])
        XCTAssertEqual(probe.enabled, [false, false, false])
        secondBinding.wrappedValue = 12
        XCTAssertEqual(firstBinding.wrappedValue, 9)
        XCTAssertEqual(secondBinding.wrappedValue, 12)
        XCTAssertEqual(source.value, 5)
        XCTAssertEqual(probe.values, [5, 5, 9, 12])
    }

    private func inlineSize<Value>(_ value: Value) -> Int { MemoryLayout<Value>.size }
}

@MainActor
private struct StorageValueLeaf: View {
    typealias Body = Never
    var label: String
    var body: Never { fatalError("Primitive") }
    func makeComponent(context: ViewBuildContext) -> Component { Component { _ in ViewNode(text: label) } }
}

@MainActor
private final class StorageMetadataProbe {
    var events: [String] = []
    var tag = "Initial"
    var bodyCalls = 0
    var componentCalls = 0
}

@MainActor
private struct StorageMetadataLeaf: View, TaggedViewMetadata, SwipeActionMetadata {
    typealias Body = Never
    let probe: StorageMetadataProbe
    var body: Never {
        unevaluatedMetadataBody()
    }

    private func unevaluatedMetadataBody() -> Never {
        probe.bodyCalls += 1
        fatalError("Metadata inspection must not evaluate the body")
    }
    func makeComponent(context: ViewBuildContext) -> Component {
        probe.componentCalls += 1
        return Component { _ in ViewNode() }
    }
    var anySelectionTag: AnyHashable? {
        probe.events.append("tag")
        return AnyHashable(probe.tag)
    }
    var anyTabItem: [AnyView]? {
        probe.events.append("tab")
        return nil
    }
    var anyBadge: [AnyView]? {
        probe.events.append("badge")
        return nil
    }
    var anyNavigationTitle: [AnyView]? {
        probe.events.append("title")
        return nil
    }
    var anyNavigationSubtitle: [AnyView]? {
        probe.events.append("subtitle")
        return nil
    }
    var anyNavigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? {
        probe.events.append("displayMode")
        return nil
    }
    var anyNavigationBarBackButtonHidden: Bool? {
        probe.events.append("backHidden")
        return nil
    }
    var anyNavigationBarHidden: Bool? {
        probe.events.append("barHidden")
        return nil
    }
    var anyToolbarItemPlacement: ToolbarItemPlacement? {
        probe.events.append("toolbar")
        return nil
    }
    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] {
        probe.events.append("destinations")
        return []
    }
    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] {
        probe.events.append("presented")
        return []
    }
    var swipeActions: [RetainedSwipeAction] {
        probe.events.append("swipe")
        return []
    }
}

@MainActor
private final class StorageLifetimeProbe {
    let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    deinit { MainActor.assumeIsolated { onRelease() } }
}

@MainActor
private struct StorageLifetimeLeaf: View {
    typealias Body = Never
    let probe: StorageLifetimeProbe
    var body: Never { fatalError("Primitive") }
    func makeComponent(context: ViewBuildContext) -> Component { Component { _ in ViewNode() } }
}

@MainActor
private final class StorageStateProbe {
    var values: [Int] = []
    var enabled: [Bool] = []
    var bindings: [Binding<Int>] = []
}

@MainActor
private struct StorageStateLeaf: View {
    @State private var count = 5
    @Environment(\.isEnabled) private var isEnabled
    let probe: StorageStateProbe
    var value: Int { count }
    var body: some View {
        probe.values.append(count)
        probe.enabled.append(isEnabled)
        probe.bindings.append($count)
        return Text("Value \(count)")
    }
}

@MainActor
private final class StorageStateHost {
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let coordinator: StateMountCoordinator
    private var closed = false

    init(content: @escaping @MainActor () -> AnyView) {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 180, height: 80)))
        let host = ComponentHost(runtime: runtime)
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() },
            observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        self.runtime = runtime
        self.host = host
        self.coordinator = coordinator
        host.buildLifecycle = coordinator
        host.shouldUpdate = { [weak self] in self?.closed == false }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { Size(width: 180, height: 80) },
            invalidateHandler: { [weak host] in host?.reload() })
        host.setComponents { [weak self] in
            guard self?.closed == false else { return [] }
            return [makeViewComponent(content(), context: context)]
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        runtime.stopRenderLifecycleCallbacks()
        coordinator.close()
        host.setComponents { [] }
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private func storageClose(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}
