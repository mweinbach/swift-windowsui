import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class RetainedLazyListPhysicalAttachmentRetirementTests: XCTestCase {
    func testContributionFreeChromeDepartureAllowsFollowingListRefresh() async throws {
        let model = PhysicalAttachmentRetirementModel()
        let capture = PhysicalAttachmentRetirementCapture()
        var selection: String? = "element"
        let binding = Binding<String?>(get: { selection }, set: { selection = $0 })
        let content = PhysicalAttachmentRetirementRoot(model: model) {
            let optional: PhysicalAttachmentRetirementTail? =
                model.includesOptional
                ? PhysicalAttachmentRetirementTail(name: "optional", seed: 3, capture: capture)
                : nil
            let tail = PhysicalAttachmentRetirementTail(name: "tail", seed: 7, capture: capture)
            let prebuilt = [AnyView(optional), AnyView(tail)]
            let list = List(["element"], id: \.self, selection: binding) { _ in
                return prebuilt
            }
            return [AnyView(list)]
        }
        let fixture = try PhysicalAttachmentRetirementWindow(content)
        defer { fixture.close() }
        let tail = try fixture.node("tail")
        let identity = try XCTUnwrap(tail.retainedViewIdentity)
        let tailBinding = try XCTUnwrap(capture.bindings["tail"])
        tailBinding.wrappedValue = 41
        fixture.flush()
        XCTAssertEqual(try fixture.node("tail").text, "41")

        // Keep only the outgoing source-free chrome alive deliberately: actual
        // departure must retire its witness without waiting for weak expiry.
        let (physical, departingChrome, original) = try fixture.lastChromeAttachment()
        let chromeStorage = try XCTUnwrap(departingChrome.retainedLazyListActivityStorage)
        XCTAssertTrue(chromeStorage.committedContributions.isEmpty)
        XCTAssertTrue(original.isAttached)

        model.includesOptional = false
        fixture.flush()

        let retained = try fixture.node("tail")
        XCTAssertTrue(retained === tail)
        XCTAssertEqual(retained.retainedViewIdentity, identity)
        XCTAssertEqual(retained.text, "41")
        XCTAssertTrue(fixture.nodes("optional").isEmpty)
        XCTAssertNil(departingChrome.parent)
        XCTAssertFalse(original.isAttached)
        XCTAssertTrue(chromeStorage.committedContributions.isEmpty)
        XCTAssertFalse(
            physical.actualAttachments.contains {
                $0.target === original.target && $0.attachment === original.attachment
            })
        try fixture.assertShrunkFootprint(physical: physical, departedChrome: departingChrome)
        XCTAssertEqual(physical.state, .active)

        let completedBeforeRefresh = fixture.acceptedListResolutions
        tailBinding.wrappedValue = 42
        fixture.flush()

        XCTAssertTrue(try fixture.node("tail") === tail)
        XCTAssertEqual(tail.text, "42")
        XCTAssertEqual(tailBinding.wrappedValue, 42)
        XCTAssertGreaterThan(fixture.acceptedListResolutions, completedBeforeRefresh)
        XCTAssertEqual(physical.state, .active)
        try fixture.assertShrunkFootprint(physical: physical, departedChrome: departingChrome)
    }

    func testOriginalIdentityInvalidationWithoutDepartureStillRejectsHandoff() async throws {
        let control = try PhysicalAttachmentRetirementHandoffFixture()
        defer { withExtendedLifetime(control) {} }
        XCTAssertTrue(control.reserve())
        _ = control.journal.seal()

        let fixture = try PhysicalAttachmentRetirementHandoffFixture()
        defer { withExtendedLifetime(fixture) {} }
        let keeper = ViewNode()
        fixture.root.addChild(keeper)
        let keeperActual = keeper.lazyListActivityStorage().captureActualAttachment(of: keeper, in: fixture.runtime)
        XCTAssertTrue(fixture.physical.activate(on: keeperActual))
        XCTAssertNotNil(fixture.attribution.registerGroup(kind: .objectDependency))
        let identity = try XCTUnwrap(fixture.rowNode.retainedViewIdentity)

        fixture.rowNode.retainedViewIdentity = identity

        XCTAssertTrue(fixture.rowNode.parent === fixture.root)
        XCTAssertEqual(fixture.rowNode.retainedViewIdentity, identity)
        XCTAssertFalse(fixture.actual.isAttached)
        XCTAssertEqual(fixture.physical.state, .active)
        XCTAssertEqual(fixture.physical.actualAttachments.count, 2)
        XCTAssertTrue(fixture.physical.actualAttachments.contains { $0 === fixture.actual })

        // A duplicate activation with a fresh query must not replace the
        // original identity witness that the complete handoff still checks.
        let duplicate = fixture.rowNode.lazyListActivityStorage().captureActualAttachment(
            of: fixture.rowNode, in: fixture.runtime)
        XCTAssertTrue(duplicate.isAttached)
        XCTAssertTrue(duplicate.attachment === fixture.actual.attachment)
        XCTAssertTrue(fixture.physical.activate(on: duplicate))
        XCTAssertEqual(fixture.physical.actualAttachments.count, 2)
        XCTAssertTrue(fixture.physical.actualAttachments.contains { $0 === fixture.actual })
        XCTAssertFalse(fixture.physical.actualAttachments.contains { $0 === duplicate })
        XCTAssertFalse(fixture.reserve())
        XCTAssertFalse(fixture.journal.markMutationStarted())
        XCTAssertFalse(fixture.journal.hasAcceptedContributions)

        // Only the subsequent real departure may remove that stale witness.
        fixture.rowNode.removeFromParent()

        XCTAssertFalse(fixture.physical.actualAttachments.contains { $0 === fixture.actual })
        XCTAssertEqual(fixture.physical.actualAttachments.count, 1)
        XCTAssertTrue(fixture.physical.actualAttachments.first === keeperActual)
        XCTAssertEqual(fixture.physical.state, .active)
        let disposition = fixture.journal.seal()
        XCTAssertEqual(disposition.stop, .noAcceptance)
        XCTAssertTrue(disposition.acceptedGroups.isEmpty)
        XCTAssertTrue(disposition.acceptedEmptyGroups.isEmpty)
        XCTAssertTrue(disposition.acceptedFacets.isEmpty)
    }

    func testOldDepartureCannotRetireReattachedSuccessorOrAnotherReceipt() async throws {
        let fixture = try PhysicalAttachmentRetirementHandoffFixture()
        defer { withExtendedLifetime(fixture) {} }
        let keeper = ViewNode()
        fixture.root.addChild(keeper)
        let keeperActual = keeper.lazyListActivityStorage().captureActualAttachment(of: keeper, in: fixture.runtime)
        XCTAssertTrue(fixture.physical.activate(on: keeperActual))
        let departure = RetainedLazyListAcceptedDeparture(
            physical: fixture.physical, formerAttachments: [fixture.actual], contributions: [],
            cause: .acceptedReplacement, cleanup: RetainedLazyListCleanupID())

        fixture.rowNode.removeFromParent()

        XCTAssertFalse(fixture.actual.isAttached)
        XCTAssertEqual(fixture.physical.actualAttachments.count, 1)
        XCTAssertEqual(fixture.physical.state, .active)
        fixture.root.addChild(fixture.rowNode)
        let successor = fixture.rowNode.lazyListActivityStorage().captureActualAttachment(
            of: fixture.rowNode, in: fixture.runtime)
        XCTAssertTrue(successor.target === fixture.actual.target)
        XCTAssertFalse(successor.attachment === fixture.actual.attachment)
        XCTAssertTrue(fixture.physical.activate(on: successor))
        let other = RetainedLazyListPhysicalActivityReceipt(membership: RetainedLazyListMembershipID())
        XCTAssertTrue(other.activate(on: successor))

        fixture.journal.recordAcceptedDeparture(departure)
        fixture.journal.recordAcceptedDeparture(departure)

        XCTAssertEqual(fixture.physical.actualAttachments.count, 2)
        XCTAssertTrue(fixture.physical.actualAttachments.contains { $0 === successor })
        XCTAssertTrue(other.actualAttachments.first === successor)
        XCTAssertTrue(successor.isAttached)
        XCTAssertEqual(other.state, .active)

        fixture.rowNode.removeFromParent()

        XCTAssertEqual(fixture.physical.actualAttachments.count, 1)
        XCTAssertTrue(fixture.physical.actualAttachments.first === keeperActual)
        XCTAssertTrue(other.actualAttachments.isEmpty)
        XCTAssertEqual(other.state, .revoked)

        // Rolling back one receipt must withdraw only its old association.
        // Reaccepting the same attachment needs its own retirement entry.
        fixture.root.addChild(fixture.rowNode)
        let rolledBack = fixture.rowNode.lazyListActivityStorage().captureActualAttachment(
            of: fixture.rowNode, in: fixture.runtime)
        XCTAssertTrue(fixture.physical.activate(on: rolledBack))
        let independent = RetainedLazyListPhysicalActivityReceipt(membership: RetainedLazyListMembershipID())
        XCTAssertTrue(independent.activate(on: rolledBack))
        fixture.physical.removeAttachment(target: rolledBack.target, attachment: rolledBack.attachment)
        XCTAssertTrue(independent.actualAttachments.first === rolledBack)
        XCTAssertEqual(independent.state, .active)
        let reaccepted = fixture.rowNode.lazyListActivityStorage().captureActualAttachment(
            of: fixture.rowNode, in: fixture.runtime)
        XCTAssertTrue(reaccepted.attachment === rolledBack.attachment)
        XCTAssertFalse(reaccepted === rolledBack)
        XCTAssertTrue(fixture.physical.activate(on: reaccepted))

        fixture.rowNode.removeFromParent()

        XCTAssertEqual(fixture.physical.actualAttachments.count, 1)
        XCTAssertTrue(fixture.physical.actualAttachments.first === keeperActual)
        XCTAssertEqual(fixture.physical.state, .active)
        XCTAssertTrue(independent.actualAttachments.isEmpty)
        XCTAssertEqual(independent.state, .revoked)
        _ = fixture.journal.seal()
    }
}

@MainActor
private final class PhysicalAttachmentRetirementModel: ObservableObject {
    @Published var includesOptional = true
}

@MainActor
private final class PhysicalAttachmentRetirementCapture {
    var bindings: [String: Binding<Int>] = [:]

    func record(_ name: String, binding: Binding<Int>) {
        bindings[name] = binding
    }
}

private struct PhysicalAttachmentRetirementRoot: View {
    @ObservedObject private var model: PhysicalAttachmentRetirementModel
    private let content: @MainActor () -> [AnyView]

    init(model: PhysicalAttachmentRetirementModel, content: @escaping @MainActor () -> [AnyView]) {
        self.model = model
        self.content = content
    }

    var body: [AnyView] {
        let _ = model.includesOptional
        return content()
    }
}

private struct PhysicalAttachmentRetirementTail: View {
    @State private var value: Int
    let name: String
    let capture: PhysicalAttachmentRetirementCapture

    init(name: String, seed: Int, capture: PhysicalAttachmentRetirementCapture) {
        self._value = State(initialValue: seed)
        self.name = name
        self.capture = capture
    }

    var body: some View {
        let current = value
        let _ = capture.record(name, binding: $value)
        Text(String(current)).accessibilityIdentifier(name)
    }
}

@MainActor
private final class PhysicalAttachmentRetirementWindow {
    private let host: WinSwiftUIWindowHost
    private let window: Win32Window
    private let clock: RuntimeTestClock

    init<Content: View>(_ content: Content) throws {
        let configuration = WindowGroupConfiguration(
            title: "Physical List attachment retirement", size: IntSize(width: 400, height: 300), clearColor: .black,
            content: [AnyView(content)])
        let clock = RuntimeTestClock()
        clock.now = 7_500
        let handle = try XCTUnwrap(NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1)))
        let surface = SurfaceDescriptor(
            windowHandle: handle, pixelSize: configuration.size, scaleFactor: 1)
        let window = Win32Window(title: configuration.title, clientSize: configuration.size)
        let host = WinSwiftUIWindowHost(
            configuration: configuration, platformWindow: window,
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.host = host
        self.window = window
        self.clock = clock
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        flush()
    }

    var acceptedListResolutions: Int { host.hostedRuntime.lazyListResolveCount }

    func flush() {
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func close() { host.windowWillClose(window) }

    func nodes(_ identifier: String) -> [ViewNode] {
        allNodes(in: host.hostedRuntime.root).filter { $0.accessibilityIdentifier == identifier }
    }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes(identifier)
        XCTAssertEqual(matches.count, 1, "Expected one node for \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    // Adapter/provider references remain within each observation, never across
    // the next original mutation or frame. Chrome carries no authored payload.
    @inline(never)
    func lastChromeAttachment() throws -> (
        RetainedLazyListPhysicalActivityReceipt, ViewNode, RetainedLazyListActualAttachment
    ) {
        let list = try listNode()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertEqual(adapter.materializedRowActivities.count, 1)
        let physical = try XCTUnwrap(adapter.materializedRowActivities.first?.physical)
        let gaps = list.children.filter { $0.retainedLazyListGap != nil }
        XCTAssertEqual(gaps.count, 2)
        let chrome = try XCTUnwrap(gaps.last)
        let actual = try XCTUnwrap(physical.actualAttachments.first { $0.node === chrome })
        XCTAssertEqual(list.children.count, 4)
        XCTAssertEqual(adapter.mountedLeafCount, 4)
        return (physical, chrome, actual)
    }

    @inline(never)
    func assertShrunkFootprint(
        physical: RetainedLazyListPhysicalActivityReceipt, departedChrome: ViewNode
    ) throws {
        let list = try listNode()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertEqual(adapter.materializedRowActivities.count, 1)
        XCTAssertTrue(adapter.materializedRowActivities.first?.physical === physical)
        XCTAssertEqual(list.children.count, 2)
        XCTAssertEqual(adapter.mountedLeafCount, 2)
        let gaps = list.children.filter { $0.retainedLazyListGap != nil }
        XCTAssertEqual(gaps.count, 1)
        let survivingChrome = try XCTUnwrap(gaps.first)
        XCTAssertFalse(survivingChrome === departedChrome)
        XCTAssertTrue(try XCTUnwrap(survivingChrome.retainedLazyListActivityStorage).committedContributions.isEmpty)
    }

    private func listNode(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = allNodes(in: host.hostedRuntime.root).filter { $0.retainedLazyListAdapter != nil }
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    private func allNodes(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { allNodes(in: $0) }
    }
}

@MainActor
private final class PhysicalAttachmentRetirementHandoffFixture {
    let root: ViewNode
    let rowNode: ViewNode
    let runtime: RetainedViewRuntime
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let physical: RetainedLazyListPhysicalActivityReceipt
    let actual: RetainedLazyListActualAttachment
    let journal: RetainedLazyListAdoptionJournal
    let attribution: RetainedLazyListBuildAttribution
    let previous: RetainedLazyListMaterializedRowActivity
    let successor: RetainedLazyListMaterializedRowActivity

    init() throws {
        let root = ViewNode()
        let rowNode = ViewNode()
        rowNode.retainedViewIdentity = RetainedViewIdentity(segments: [.slot(0)])
        root.addChild(rowNode)
        let runtime = RetainedViewRuntime(root: root)
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(source.replaceData([0], id: \.self, rowContent: { _ in [] }))
        let metadata = try XCTUnwrap(source.metadata)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: root.lazyListActivityStorage().descriptorOwnerLifetime)
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
        let membership = try XCTUnwrap(logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let descriptorJournal = RetainedLazyListAdoptionJournal(
            descriptorScope: scope, transaction: RetainedBuildTransaction())
        let binding = RetainedLazyListManagedLogicalDescriptorBinding(
            descriptor: RetainedLazyListLogicalDeclarationID(), facadeProposal: RetainedLazyListLogicalProposalID(),
            scope: logical, metadata: metadata)
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        XCTAssertTrue(adapter.installManagedLogicalDescriptor(binding))
        let descriptorSource = ViewNode()
        descriptorSource.retainedLazyListAdapter = adapter
        XCTAssertNotNil(descriptorJournal.registerSourceDescriptor(binding, on: descriptorSource))
        let preparation = try XCTUnwrap(descriptorJournal.preparation())
        let snapshot = try XCTUnwrap(preparation.logicalSnapshots.first { $0.scope === logical })
        let plan = try XCTUnwrap(
            RetainedLazyListLogicalMembershipPlan(
                descriptor: binding.descriptor, facadeProposal: binding.facadeProposal,
                expected: snapshot, sourceGeneration: metadata.generation,
                introduced: [membership], retained: [], deleted: []))
        XCTAssertTrue(
            descriptorJournal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(
                    preparation: preparation, logicalMembershipPlans: [plan])))
        guard case .ready(let publication) = descriptorJournal.prepareDescriptorCopy(from: descriptorSource, to: root)
        else { throw PhysicalAttachmentRetirementError.descriptor }
        XCTAssertTrue(descriptorJournal.markMutationStarted())
        XCTAssertNotNil(descriptorJournal.recordAcceptedLogicalDeclaration(publication))
        _ = descriptorJournal.seal(completedCheckedAdoption: true)
        scope.finish()
        XCTAssertTrue(membership.isDeclared)

        let physical = RetainedLazyListPhysicalActivityReceipt(membership: membership.id)
        let actual = rowNode.lazyListActivityStorage().captureActualAttachment(of: rowNode, in: runtime)
        XCTAssertTrue(physical.activate(on: actual))
        let request = try XCTUnwrap(source.request(for: try XCTUnwrap(metadata.rows.first?.token)))
        let oldAttribution = RetainedLazyListBuildAttribution(
            journal: descriptorJournal, rowRequest: request, logicalMembership: membership, physical: physical,
            component: RetainedLazyListComponentID(), resolutionID: RetainedLazyListRowResolutionID(),
            origin: .selectedRow)
        let replacementScope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: root.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(
            descriptorScope: replacementScope, transaction: RetainedBuildTransaction())
        let parent = RetainedLazyListBuildAttribution(
            journal: journal, rowRequest: request, logicalMembership: membership, physical: physical,
            component: RetainedLazyListComponentID(), resolutionID: RetainedLazyListRowResolutionID(),
            origin: .selectedRow)
        let attribution = try XCTUnwrap(parent.registerChildComponent())
        self.root = root
        self.rowNode = rowNode
        self.runtime = runtime
        self.source = source
        self.physical = physical
        self.actual = actual
        self.journal = journal
        self.attribution = attribution
        previous = RetainedLazyListMaterializedRowActivity(oldAttribution)
        successor = RetainedLazyListMaterializedRowActivity(attribution)
    }

    func reserve() -> Bool {
        journal.prepareRowReplacementHandoff(from: previous, to: successor)
    }
}

private enum PhysicalAttachmentRetirementError: Error {
    case descriptor
}
