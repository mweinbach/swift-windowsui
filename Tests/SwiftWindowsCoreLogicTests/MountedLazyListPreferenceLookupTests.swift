import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Exercises the public preference modifiers inside a held construction epoch.
/// These source fixtures do not claim adoption, rendering, or native-host timing.
@MainActor
final class MountedLazyListPreferenceLookupTests: XCTestCase {
    func testDescriptorFirstDefaultReentryStopsPreferenceTraversalAndKeepsNestedState() async throws {
        try assertPreferenceReentry(mode: .descriptor, trigger: .defaultGetter)
    }

    func testDescriptorFirstReducerReentryStopsPreferenceTraversalAndKeepsNestedState() async throws {
        try assertPreferenceReentry(mode: .descriptor, trigger: .reducer)
    }

    func testLazyFirstDefaultReentryStopsPreferenceTraversalAndKeepsNestedState() async throws {
        try assertPreferenceReentry(mode: .lazy, trigger: .defaultGetter)
    }

    func testLazyFirstReducerReentryStopsPreferenceTraversalAndKeepsNestedState() async throws {
        try assertPreferenceReentry(mode: .lazy, trigger: .reducer)
    }

    private func assertPreferenceReentry(
        mode: MountedPreferenceLookupMode, trigger: MountedPreferenceLookupTrigger,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try MountedPreferenceLookupFixture()
        let probe = MountedPreferenceLookupProbe(trigger: trigger)
        let selection: MountedPreferenceLookupSelection?
        let context: ViewBuildContext
        switch mode {
        case .descriptor:
            selection = nil
            context = try fixture.descriptorContext()
        case .lazy:
            let selected = try MountedPreferenceLookupSelection(fixture: fixture, probe: probe)
            selection = selected
            context = try selected.enterRow()
        }
        let route = try MountedPreferenceLookupRoute(context: context)
        let previousProbe = MountedPreferenceLookupKey.probe
        MountedPreferenceLookupKey.probe = probe
        defer {
            MountedPreferenceLookupKey.probe = previousProbe
            probe.onReentry = nil
            selection?.close()
            fixture.close()
            probe.nestedOutput = nil
        }

        var nested: MountedPreferenceLookupInstalledState?
        var originalLookup: LazyListLookupReceipt?
        var hookError: Error?
        var attributionSurvivedReentry = false
        probe.onReentry = {
            originalLookup = route.lookup(in: fixture.coordinator)
            do {
                // Use the existing nil-attribution State installation route.
                // Its legitimate map publication must invalidate the interrupted
                // preference lookup without superseding this construction epoch.
                nested = try fixture.installOrdinarySibling()
                attributionSurvivedReentry = route.isCurrent
                probe.nestedOutput = materializePreferenceLookup(
                    label: .nested, values: [31, 42], probe: probe,
                    context: context.withViewIdentityRole(.overlay), runtime: fixture.runtime)
            } catch {
                hookError = error
            }
        }

        let output = materializePreferenceLookup(
            label: .outer, values: [11, 22], probe: probe, context: context, runtime: fixture.runtime)
        probe.onReentry = nil
        if let hookError { throw hookError }

        XCTAssertEqual(probe.hookCalls, 1, file: file, line: line)
        XCTAssertTrue(probe.callbacksAfterReentry.isEmpty, file: file, line: line)
        switch trigger {
        case .defaultGetter:
            XCTAssertEqual(probe.outerCallbacks, ["default"], file: file, line: line)
        case .reducer:
            XCTAssertEqual(
                probe.outerCallbacks.filter { $0.hasPrefix("reduce:") }, ["reduce:11"], file: file, line: line)
            XCTAssertEqual(probe.outerCallbacks.last, "reduce:11", file: file, line: line)
        }
        XCTAssertTrue(
            probe.nestedCallbacks.contains("reduce:42"),
            "The nested public observer must finish its own bounded preference traversal", file: file, line: line)
        XCTAssertTrue(attributionSurvivedReentry, file: file, line: line)
        XCTAssertTrue(route.isCurrent, file: file, line: line)
        XCTAssertFalse(try XCTUnwrap(originalLookup, file: file, line: line).isCurrent, file: file, line: line)
        XCTAssertTrue(fixture.build.canAdopt, file: file, line: line)
        XCTAssertFalse(fixture.coordinator.registry.isClosed, file: file, line: line)
        XCTAssertFalse(output.containsRejectedRetainedSource, file: file, line: line)
        XCTAssertFalse(
            try XCTUnwrap(probe.nestedOutput, file: file, line: line).containsRejectedRetainedSource, file: file,
            line: line)

        // Both public source Components have left their non-inlined scopes.
        // A staged OnChangeUpdate is now the only owner of its action capture.
        // Reject the stale outer update rather than retaining it until finish.
        XCTAssertNil(probe.outerAction, file: file, line: line)
        XCTAssertNotNil(probe.nestedAction, file: file, line: line)
        XCTAssertEqual(probe.releasedActions, ["outer"], file: file, line: line)
        XCTAssertTrue(probe.deliveredValues.isEmpty, file: file, line: line)

        let installed = try XCTUnwrap(nested, file: file, line: line)
        XCTAssertTrue(installed.epoch === fixture.epoch, file: file, line: line)
        XCTAssertTrue(installed.owner.isInstallationActive, file: file, line: line)
        XCTAssertTrue(fixture.epoch.visitedOwnerIdentities.contains(installed.owner.identity), file: file, line: line)
        XCTAssertEqual(installed.value.wrappedValue, 23, file: file, line: line)
        installed.value.wrappedValue = 71
        XCTAssertEqual(
            installed.value.wrappedValue, 71,
            "An interrupted observer cannot overwrite the nested State installation", file: file, line: line)
        XCTAssertEqual(probe.rowFactories, 0, file: file, line: line)

        selection?.close()
        fixture.close()
        XCTAssertNil(probe.nestedAction, file: file, line: line)
        XCTAssertEqual(probe.releasedActions, ["outer", "nested"], file: file, line: line)
        XCTAssertTrue(probe.deliveredValues.isEmpty, file: file, line: line)
        withExtendedLifetime((output, probe.nestedOutput)) {}
    }
}

private enum MountedPreferenceLookupMode {
    case descriptor
    case lazy
}

private enum MountedPreferenceLookupTrigger {
    case defaultGetter
    case reducer

    func matches(_ callback: String) -> Bool {
        switch self {
        case .defaultGetter: return callback == "default"
        case .reducer: return callback.hasPrefix("reduce:")
        }
    }
}

private enum MountedPreferenceLookupLabel: String {
    case outer
    case nested
}

@MainActor
private final class MountedPreferenceLookupProbe {
    let trigger: MountedPreferenceLookupTrigger
    var label = MountedPreferenceLookupLabel.outer
    var onReentry: (@MainActor () -> Void)?
    private(set) var hookCalls = 0
    private var returnedFromReentry = false
    private(set) var outerCallbacks: [String] = []
    private(set) var nestedCallbacks: [String] = []
    private(set) var callbacksAfterReentry: [String] = []
    var releasedActions: [String] = []
    var deliveredValues: [Int] = []
    var nestedOutput: ViewNode?
    var rowFactories = 0
    weak var outerAction: MountedPreferenceLookupAction?
    weak var nestedAction: MountedPreferenceLookupAction?

    init(trigger: MountedPreferenceLookupTrigger) { self.trigger = trigger }

    func record(_ callback: String) {
        switch label {
        case .outer:
            outerCallbacks.append(callback)
            if returnedFromReentry { callbacksAfterReentry.append(callback) }
        case .nested:
            nestedCallbacks.append(callback)
        }
        guard label == .outer, trigger.matches(callback), let action = onReentry else { return }
        onReentry = nil
        hookCalls += 1
        action()
        returnedFromReentry = true
    }
}

private struct MountedPreferenceLookupKey: PreferenceKey {
    @MainActor static var probe: MountedPreferenceLookupProbe?

    static var defaultValue: Int {
        MainActor.assumeIsolated { probe?.record("default") }
        return 0
    }

    static func reduce(value: inout Int, nextValue: () -> Int) {
        let next = nextValue()
        value = next
        MainActor.assumeIsolated { probe?.record("reduce:\(next)") }
    }
}

@MainActor
private final class MountedPreferenceLookupAction {
    let label: MountedPreferenceLookupLabel
    let probe: MountedPreferenceLookupProbe

    init(label: MountedPreferenceLookupLabel, probe: MountedPreferenceLookupProbe) {
        self.label = label
        self.probe = probe
    }

    func deliver(_ value: Int) { probe.deliveredValues.append(value) }
    isolated deinit { probe.releasedActions.append(label.rawValue) }
}

/// A fixed two-leaf tree makes a skipped sibling observable without evaluating
/// a List body or invoking a preference callback directly in the test.
@MainActor
private struct MountedPreferenceLookupForest: View {
    typealias Body = Never
    let values: [Int]

    var body: Never { fatalError("The preference fixture has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let root = ViewNode()
            for (index, value) in values.enumerated() {
                let child = Color.clear.preference(key: MountedPreferenceLookupKey.self, value: value)
                    .makeComponent(context: context.withViewIdentityPrefix([.slot(index)]))
                root.addChild(child.makeNode(runtime: runtime))
            }
            return root
        }
    }
}

@MainActor
@inline(never)
private func materializePreferenceLookup(
    label: MountedPreferenceLookupLabel, values: [Int], probe: MountedPreferenceLookupProbe,
    context: ViewBuildContext, runtime: RetainedViewRuntime
) -> ViewNode {
    let previous = probe.label
    probe.label = label
    defer { probe.label = previous }
    let action = MountedPreferenceLookupAction(label: label, probe: probe)
    switch label {
    case .outer: probe.outerAction = action
    case .nested: probe.nestedAction = action
    }
    let source = MountedPreferenceLookupForest(values: values)
        .onPreferenceChange(MountedPreferenceLookupKey.self) { [action] value in action.deliver(value) }
    return source.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private enum MountedPreferenceLookupRoute {
    case descriptor(RetainedDescriptorComponentAttribution)
    case lazy(LazyListViewAttribution)

    init(context: ViewBuildContext) throws {
        if let lazy = context.viewIdentity.lazyList {
            self = .lazy(lazy)
        } else {
            self = .descriptor(try XCTUnwrap(context.viewIdentity.descriptorComponent))
        }
    }

    var isCurrent: Bool {
        switch self {
        case .descriptor(let attribution): return attribution.canConstruct
        case .lazy(let attribution): return attribution.isCurrent
        }
    }

    func lookup(in coordinator: StateMountCoordinator) -> LazyListLookupReceipt? {
        switch self {
        case .descriptor(let attribution): return coordinator.descriptorLookupReceipt(for: attribution)
        case .lazy(let attribution): return attribution.admission.beginLookup()
        }
    }
}

/// Mirrors the held-epoch harness in the checked-key/continuation suites. The
/// ordinary root context is kept separate from each managed observer context.
@MainActor
private final class MountedPreferenceLookupFixture {
    let coordinator: StateMountCoordinator
    let build: any RetainedBuildEpoch
    let epoch: StateMountEpoch
    let activity: any RetainedLazyListBuildActivity
    let scope: RetainedLazyListDescriptorBuildScope
    let target: ViewNode
    let runtime: RetainedViewRuntime
    let context: ViewBuildContext
    private var isClosed = false

    init() throws {
        let coordinator = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        let build = try XCTUnwrap(coordinator.beginBuild())
        let activity = try XCTUnwrap(build as? any RetainedLazyListBuildActivity)
        let target = ViewNode()
        let runtime = RetainedViewRuntime(root: target)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: target.lazyListActivityStorage().descriptorOwnerLifetime)
        XCTAssertTrue(activity.bindLazyListDescriptorScope(scope))
        var context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { Size(width: 120, height: 40) },
            invalidateHandler: {}
        ).withViewIdentityType(MountedPreferenceLookupRoot.self)
        _ = try XCTUnwrap(coordinator.install(MountedPreferenceLookupRoot(), context: &context))
        self.coordinator = coordinator
        self.build = build
        self.epoch = try XCTUnwrap(context.viewIdentity.installedEpoch)
        self.activity = activity
        self.scope = scope
        self.target = target
        self.runtime = runtime
        self.context = context
    }

    func descriptorContext() throws -> ViewBuildContext {
        let source = context.withViewIdentityRole(.body).withViewIdentityType(MountedPreferenceLookupRoot.self)
        var described = try XCTUnwrap(coordinator.contextForDescriptorComponent(from: source))
        _ = try XCTUnwrap(coordinator.install(MountedPreferenceLookupRoot(), context: &described))
        return described
    }

    func installOrdinarySibling() throws -> MountedPreferenceLookupInstalledState {
        var sibling = context.withViewIdentityRole(.overlay).withViewIdentityType(MountedPreferenceLookupState.self)
        let value = try XCTUnwrap(coordinator.install(MountedPreferenceLookupState(), context: &sibling))
        return MountedPreferenceLookupInstalledState(
            owner: try XCTUnwrap(sibling.viewIdentity.installedOwner),
            epoch: try XCTUnwrap(sibling.viewIdentity.installedEpoch), value: value.$value)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        coordinator.close()
        build.abandon()
        build.finishAfterCallbacks()
    }
}

@MainActor
private final class MountedPreferenceLookupSelection {
    let fixture: MountedPreferenceLookupFixture
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let binding: RetainedLazyListManagedLogicalDescriptorBinding
    let adapter: RetainedLazyListRuntimeAdapter
    let nativeCoordinator: RetainedBuildCoordinator
    let admission: RetainedLazyListAdoptionAdmission
    let journal: RetainedLazyListAdoptionJournal
    private let lease: MountedPreferenceLookupLease
    private var isClosed = false

    init(fixture: MountedPreferenceLookupFixture, probe: MountedPreferenceLookupProbe) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        let identity = fixture.context.retainedViewIdentity.appending(.role(.content))
        XCTAssertTrue(
            provider.replaceData(
                [0], id: \.self, identityRoot: identity, descriptorBuildScope: fixture.scope,
                rowContent: { _, _ in
                    probe.rowFactories += 1
                    return []
                }))
        let metadata = try XCTUnwrap(provider.metadata)
        let proposal = try XCTUnwrap(
            fixture.coordinator.stageLazyMembership(
                at: identity, metadata: metadata, context: fixture.context, receipt: receipt))
        let binding = proposal.nativeBinding
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 4, maximumProtectedRecords: 1))
        XCTAssertTrue(adapter.installManagedLogicalDescriptor(binding))
        let lease = MountedPreferenceLookupLease()
        fixture.target.retainedSubtreeBuildLease = lease
        fixture.target.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.claimAttachment(to: fixture.target))
        let nativeCoordinator = RetainedBuildCoordinator()
        let sequence = try XCTUnwrap(nativeCoordinator.beginBuild())
        nativeCoordinator.install(fixture.build, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: fixture.target, runtime: fixture.runtime,
            coordinator: nativeCoordinator, sequence: sequence)
        XCTAssertTrue(admission.isBuildCurrent)
        let journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: RetainedBuildTransaction())
        XCTAssertTrue(journal.bindDescriptorScope(fixture.scope))
        self.fixture = fixture
        self.provider = provider
        self.binding = binding
        self.adapter = adapter
        self.nativeCoordinator = nativeCoordinator
        self.admission = admission
        self.journal = journal
        self.lease = lease
    }

    func enterRow() throws -> ViewBuildContext {
        let metadata = try XCTUnwrap(provider.metadata)
        let request = try XCTUnwrap(provider.request(for: try XCTUnwrap(metadata.rows.first).token))
        let preparation = try XCTUnwrap(journal.prepareSelectedRow(request: request, descriptor: binding))
        let response = try XCTUnwrap(fixture.activity.resolveSelectedLazyListRow(preparation))
        let native = try XCTUnwrap(journal.consumeSelectedRowResolution(response, for: preparation))
        XCTAssertTrue(fixture.activity.enterLazyListMaterialization(native))
        var context = try XCTUnwrap(
            fixture.coordinator.contextForEnteredLazyRow(from: fixture.context, descriptor: binding))
        context.viewIdentity.path = try XCTUnwrap(provider.identityPrefix(for: request))
        return context
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        journal.revokeBeforeAbandon()
        admission.revoke()
        fixture.close()
        provider.close()
        nativeCoordinator.finishBuild()
    }
}

private struct MountedPreferenceLookupRoot {}

@MainActor
private struct MountedPreferenceLookupState {
    @State var value = 23
}

@MainActor
private struct MountedPreferenceLookupInstalledState {
    let owner: StateMountOwner
    let epoch: StateMountEpoch
    let value: Binding<Int>
}

@MainActor
private final class MountedPreferenceLookupLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { nil }
}
