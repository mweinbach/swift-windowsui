import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedLazyListReentryTests: XCTestCase {
    func testDescriptorResolutionRequiresTheNativeScopeBeforeAnyRowExists() async throws {
        let fixture = try LazyListReentryFixture(bindNativeScope: false)
        defer { fixture.close() }
        XCTAssertNil(fixture.context.viewIdentity.lazyList)
        XCTAssertNil(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        XCTAssertTrue(fixture.activity.bindLazyListDescriptorScope(fixture.scope))
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        XCTAssertTrue(receipt.isCurrent)
        XCTAssertTrue(receipt.nativeScope === fixture.scope)
        XCTAssertNil(fixture.context.viewIdentity.lazyList, "A descriptor is not a fabricated row occurrence")
    }

    func testASecondDescriptorScopeCannotReplaceTheOriginalBuildScope() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let otherLifetime = RetainedLazyListLogicalHostLifetime()
        let otherScope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: otherLifetime,
            ownerLifetime: RetainedLazyListDescriptorOwnerLifetime(
                target: RetainedLazyListTargetID(), attachment: RetainedLazyListAttachmentID()))
        XCTAssertFalse(fixture.activity.bindLazyListDescriptorScope(otherScope))
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        XCTAssertTrue(receipt.nativeScope === fixture.scope)
        XCTAssertTrue(receipt.isCurrent)
        withExtendedLifetime(otherLifetime) {}
    }

    func testDescriptorReceiptRejectsAContextInstalledByAnotherCoordinator() async throws {
        let first = try LazyListReentryFixture()
        let second = try LazyListReentryFixture()
        defer {
            first.close()
            second.close()
        }
        XCTAssertNotNil(first.coordinator.descriptorResolutionReceipt(in: first.context))
        XCTAssertNotNil(second.coordinator.descriptorResolutionReceipt(in: second.context))
        XCTAssertNil(first.coordinator.descriptorResolutionReceipt(in: second.context))
        XCTAssertNil(second.coordinator.descriptorResolutionReceipt(in: first.context))
    }

    func testOrdinaryInstallationChangesLookupRevisionWithoutExpiringDescriptorLifetime() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let lifetime = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        let oldLookup = try XCTUnwrap(lifetime.beginLookup())
        XCTAssertTrue(oldLookup.isCurrent)
        _ = try fixture.installSibling()
        XCTAssertFalse(oldLookup.isCurrent, "A map operation must not accept a nested publication as its own")
        XCTAssertTrue(lifetime.isCurrent, "A successful sibling installation does not revoke the original build")
        let nextLookup = try XCTUnwrap(lifetime.beginLookup())
        XCTAssertTrue(nextLookup.isCurrent)
        XCTAssertFalse(oldLookup.isCurrent, "A newer operation must not revive an already rejected one")
    }

    func testSupersessionRejectsTheOriginalDescriptorReceiptWithoutReplacingIt() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        let lookup = try XCTUnwrap(receipt.beginLookup())
        fixture.build.supersede()
        XCTAssertFalse(receipt.isCurrent)
        XCTAssertFalse(lookup.isCurrent)
        XCTAssertNil(receipt.beginLookup())
        XCTAssertNil(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        XCTAssertFalse(fixture.activity.bindLazyListDescriptorScope(fixture.scope))
    }

    func testOwnerCloseRevokesDescriptorAuthorityBeforeStatePayloadCleanup() async throws {
        let fixture = try LazyListReentryFixture()
        let events = LazyListReentryEvents()
        let scope = fixture.scope
        try fixture.installPayload {
            events.releases += 1
            events.constructionAtRelease.append(scope.canConstructDescriptors)
            events.publicationAtRelease.append(scope.canPublishDescriptors)
        }
        fixture.close()
        XCTAssertFalse(scope.canConstructDescriptors)
        XCTAssertFalse(scope.canPublishDescriptors)
        XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
        XCTAssertEqual(events.releases, 1)
        XCTAssertEqual(events.constructionAtRelease, [false])
        XCTAssertEqual(events.publicationAtRelease, [false])
        fixture.close()
        fixture.build.finishAfterCallbacks()
        XCTAssertEqual(events.releases, 1, "Repeated finish cannot drain the same captured payload again")
    }

    func testFinishedBuildReceiptCannotBorrowAReplacementBuildAtTheSamePath() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let originalContext = fixture.context
        let original = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: originalContext))
        fixture.abandon()
        let next = try XCTUnwrap(fixture.coordinator.beginBuild())
        defer {
            next.abandon()
            next.finishAfterCallbacks()
        }
        XCTAssertFalse(original.isCurrent)
        XCTAssertNil(original.beginLookup())
        XCTAssertNil(fixture.coordinator.descriptorResolutionReceipt(in: originalContext))
    }

    func testCloseDuringDescriptorIdentityHashDoesNotPublishTheProposal() async throws {
        let fixture = try LazyListReentryFixture()
        let gate = LazyListReentryHashGate()
        let provider = RetainedLazyListDataSource<Int, Int>()
        defer {
            gate.disarm()
            provider.close()
            fixture.close()
        }
        let context = try fixture.descriptorContext(hashing: gate, value: 17)
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: context))
        var factoryCalls = 0
        XCTAssertTrue(
            provider.replaceData([1, 2], id: \.self) { value in
                factoryCalls += 1
                return value
            })
        let metadata = try XCTUnwrap(provider.metadata)
        gate.arm { fixture.coordinator.close() }
        let proposal = fixture.coordinator.stageLazyMembership(
            at: context.retainedViewIdentity, metadata: metadata, context: context, receipt: receipt)
        gate.disarm()
        XCTAssertEqual(gate.firings, 1)
        XCTAssertNil(proposal)
        XCTAssertFalse(receipt.isCurrent)
        XCTAssertTrue(fixture.coordinator.registry.isClosed)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertEqual(fixture.coordinator.registry.liveOwnerCount, 0)
    }

    func testSupersessionDuringDescriptorIdentityHashRejectsWithoutEnteringRowContent() async throws {
        let fixture = try LazyListReentryFixture()
        let gate = LazyListReentryHashGate()
        let provider = RetainedLazyListDataSource<Int, Int>()
        defer {
            gate.disarm()
            provider.close()
            fixture.close()
        }
        let context = try fixture.descriptorContext(hashing: gate, value: 18)
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: context))
        var factoryCalls = 0
        XCTAssertTrue(
            provider.replaceData([1], id: \.self) { value in
                factoryCalls += 1
                return value
            })
        let metadata = try XCTUnwrap(provider.metadata)
        gate.arm { fixture.build.supersede() }
        XCTAssertNil(
            fixture.coordinator.stageLazyMembership(
                at: context.retainedViewIdentity, metadata: metadata, context: context, receipt: receipt))
        gate.disarm()
        XCTAssertEqual(gate.firings, 1)
        XCTAssertFalse(receipt.isCurrent)
        XCTAssertFalse(fixture.build.canAdopt)
        XCTAssertFalse(fixture.coordinator.registry.isClosed)
        XCTAssertEqual(factoryCalls, 0)
    }

    func testNestedInstallationDuringDescriptorHashSurvivesRejectedOuterPublication() async throws {
        let fixture = try LazyListReentryFixture()
        let gate = LazyListReentryHashGate()
        let provider = RetainedLazyListDataSource<Int, Int>()
        defer {
            gate.disarm()
            provider.close()
            fixture.close()
        }
        let context = try fixture.descriptorContext(hashing: gate, value: 19)
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: context))
        XCTAssertTrue(provider.replaceData([1], id: \.self) { $0 })
        let metadata = try XCTUnwrap(provider.metadata)
        var nested: StateMountOwner?
        gate.arm { nested = try? fixture.installSibling() }
        XCTAssertNil(
            fixture.coordinator.stageLazyMembership(
                at: context.retainedViewIdentity, metadata: metadata, context: context, receipt: receipt))
        gate.disarm()
        XCTAssertEqual(gate.firings, 1)
        XCTAssertTrue(receipt.isCurrent)
        let owner = try XCTUnwrap(nested)
        XCTAssertTrue(fixture.build.willAdopt())
        fixture.build.commit()
        fixture.finishCommitted()
        XCTAssertTrue(owner.isLive)
        XCTAssertTrue(fixture.coordinator.registry.owner(at: owner.identity) === owner)
    }

    func testFreshDescriptorLookupDoesNotResurrectAnExplicitlyRejectedOperation() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        let first = try XCTUnwrap(receipt.beginLookup())
        _ = try fixture.installSibling()
        XCTAssertFalse(first.isCurrent)
        let second = try XCTUnwrap(receipt.beginLookup())
        XCTAssertTrue(second.isCurrent)
        fixture.coordinator.close()
        XCTAssertFalse(first.isCurrent)
        XCTAssertFalse(second.isCurrent)
        XCTAssertNil(receipt.beginLookup())
    }

    func testRejectedDescriptorComponentCannotRequestMetadataOrReuseItsInstalledDelegate() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let context = try fixture.installDescriptorSibling()
        let attribution = try XCTUnwrap(context.viewIdentity.descriptorComponent)
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: context))
        XCTAssertNotNil(fixture.coordinator.contextForDescriptorComponent(from: context, isInstalledDelegate: true))

        attribution.rejectConstruction()

        XCTAssertFalse(attribution.canConstruct)
        XCTAssertFalse(receipt.isCurrent)
        XCTAssertNil(fixture.coordinator.descriptorResolutionReceipt(in: context))
        XCTAssertNil(fixture.coordinator.contextForDescriptorComponent(from: context, isInstalledDelegate: true))
        XCTAssertNil(fixture.coordinator.contextForAdmittedLazySubtree(from: context, lease: nil))
        XCTAssertTrue(fixture.scope.canConstructDescriptors, "An unrelated root scope cannot revive this component")
    }

    func testDescriptorOccurrenceHashCannotRenewAfterAnUnrelatedNestedInstallation() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let context = try fixture.installDescriptorSibling()
        let attribution = try XCTUnwrap(context.viewIdentity.descriptorComponent)
        let gate = LazyListReentryHashGate()
        let views = [
            AnyView(EmptyView()).prefixedViewIdentity([
                .explicit(.init(LazyListReentryHashKey(value: 31, gate: gate)))
            ])
        ]
        var nested: StateMountOwner?
        gate.arm { nested = try? fixture.installSibling() }

        XCTAssertNil(
            viewIdentityOccurrences(
                views, lazyAttribution: nil, descriptorAttribution: attribution, coordinator: fixture.coordinator))

        gate.disarm()
        XCTAssertEqual(gate.firings, 1)
        XCTAssertTrue(try XCTUnwrap(nested).isInstallationActive)
        XCTAssertFalse(attribution.canConstruct)
        XCTAssertNil(fixture.coordinator.descriptorResolutionReceipt(in: context))
    }

    func testDescriptorStructuralRejectionKeepsTheFailureMarkerVisibleToItsParent() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let context = try fixture.installDescriptorSibling()
        let attribution = try XCTUnwrap(context.viewIdentity.descriptorComponent)
        let rejectedOutput = ViewNode()
        let component = Component(
            makeViewNode: { _ in rejectedOutput },
            appendStructuralChildren: { _, nodes in
                nodes.append(rejectedOutput)
                attribution.rejectConstruction()
            })
        let preserved = preservingViewIdentity(of: component, context: context)
        var output: [ViewNode] = []

        preserved.appendChildNodes(runtime: fixture.runtime, to: &output)

        XCTAssertEqual(output.count, 1)
        XCTAssertFalse(output.first === rejectedOutput)
        XCTAssertTrue(try XCTUnwrap(output.first).containsRejectedRetainedSource)
    }

    func testFacadeSupersessionBlocksASavedDescriptorFactoryBeforeItRuns() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let context = try fixture.installDescriptorSibling()
        let attribution = try XCTUnwrap(context.viewIdentity.descriptorComponent)
        var factoryCalls = 0
        let component = preservingViewIdentity(
            of: Component { _ in
                factoryCalls += 1
                return ViewNode()
            }, context: context)

        fixture.build.supersede()
        let output = component.makeNode(runtime: fixture.runtime)

        XCTAssertFalse(fixture.scope.canConstructDescriptors)
        XCTAssertFalse(attribution.canConstruct)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertTrue(output.containsRejectedRetainedSource)
    }

    func testSelectedPreparationRequiresItsOriginalDescriptorBuildScope() async throws {
        let selected = try LazyListSelectedReentryFixture()
        let other = try LazyListReentryFixture()
        defer {
            selected.close()
            other.close()
        }
        let preparation = try selected.prepareRow(0)
        XCTAssertFalse(selected.journal.attempt === selected.facade.scope.attempt)
        XCTAssertTrue(preparation.descriptorBuildAttemptID === selected.facade.scope.attempt)
        XCTAssertNil(other.activity.resolveSelectedLazyListRow(preparation))
        XCTAssertNotNil(selected.facade.activity.resolveSelectedLazyListRow(preparation))
        XCTAssertEqual(selected.events.factoryCalls, 0)
    }

    func testCloseDuringSelectedRowHashRejectsTheRegisteredFrameBeforeAnyFactory() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let first = try selected.enterRow(0)
        selected.facade.activity.leaveLazyListMaterialization(first.attribution.native)
        let preparation = try selected.prepareRow(1)
        selected.gate.arm { selected.facade.coordinator.close() }

        XCTAssertNil(selected.facade.activity.resolveSelectedLazyListRow(preparation))

        selected.gate.disarm()
        XCTAssertEqual(selected.gate.firings, 1)
        XCTAssertFalse(first.attribution.isCurrent)
        XCTAssertNil(
            selected.facade.coordinator.contextForEnteredLazyRow(
                from: selected.facade.context, descriptor: selected.binding))
        XCTAssertEqual(selected.events.factoryCalls, 0)
        XCTAssertEqual(selected.facade.coordinator.registry.liveOwnerCount, 0)
    }

    func testDiscardDuringSelectedRowHashRevokesTheUnkeyedFrameWithoutClosingTheHost() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let first = try selected.enterRow(0)
        selected.facade.activity.leaveLazyListMaterialization(first.attribution.native)
        let preparation = try selected.prepareRow(1)
        selected.gate.arm {
            selected.facade.coordinator.discardUnadoptedSubtree(
                at: selected.proposal.listIdentity, preserveCommitted: true, lazyAttribution: first.attribution)
        }

        XCTAssertNil(selected.facade.activity.resolveSelectedLazyListRow(preparation))

        selected.gate.disarm()
        XCTAssertEqual(selected.gate.firings, 1)
        XCTAssertFalse(first.attribution.isCurrent)
        XCTAssertFalse(selected.facade.coordinator.registry.isClosed)
        XCTAssertTrue(selected.facade.scope.canConstructDescriptors)
        XCTAssertEqual(selected.events.factoryCalls, 0)
    }

    func testNestedInstallationDuringSelectedRowHashDoesNotRenewTheOuterLookup() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let first = try selected.enterRow(0)
        selected.facade.activity.leaveLazyListMaterialization(first.attribution.native)
        let preparation = try selected.prepareRow(1)
        var nested: StateMountOwner?
        selected.gate.arm { nested = try? selected.facade.installSibling() }

        XCTAssertNil(selected.facade.activity.resolveSelectedLazyListRow(preparation))

        selected.gate.disarm()
        XCTAssertEqual(selected.gate.firings, 1)
        XCTAssertTrue(try XCTUnwrap(nested).isInstallationActive)
        XCTAssertTrue(first.attribution.isCurrent, "An unrelated installation does not revoke an earlier row")
        XCTAssertEqual(selected.events.factoryCalls, 0)
    }

    func testMismatchedLeaveRevokesEveryEnteredContextWithoutBorrowingTheTopFrame() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let first = try selected.enterRow(0)
        let second = try selected.enterRow(1)

        selected.facade.activity.leaveLazyListMaterialization(first.attribution.native)

        XCTAssertFalse(first.attribution.isCurrent)
        XCTAssertFalse(second.attribution.isCurrent)
        XCTAssertNil(
            selected.facade.coordinator.contextForEnteredLazyRow(
                from: selected.facade.context, descriptor: selected.binding))
        XCTAssertFalse(selected.facade.activity.enterLazyListMaterialization(second.attribution.native))
    }

    func testRejectedLazyDependencyDoesNotSubscribeThroughTheOuterCoordinator() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        var entered = try selected.enterRow(0)
        let group = try XCTUnwrap(entered.attribution.native.registerGroup(kind: .objectDependency))
        let object = LazyListReentryObservedObject()
        let foreignOwner = try XCTUnwrap(selected.facade.context.viewIdentity.installedOwner)
        selected.facade.coordinator.stageLazyDependency(
            object, owner: foreignOwner, attribution: entered.attribution, group: group)
        XCTAssertEqual(selected.events.subscriptions, 0)

        entered.context = entered.context.withViewIdentityType(LazyListReentryOwner.self)
        _ = try XCTUnwrap(selected.facade.coordinator.install(LazyListReentryOwner(), context: &entered.context))
        let owner = try XCTUnwrap(entered.context.viewIdentity.installedOwner)
        selected.facade.coordinator.stageLazyDependency(
            object, owner: owner, attribution: entered.attribution, group: group)
        XCTAssertEqual(selected.events.subscriptions, 1)

        entered.attribution.admission.reject()
        selected.facade.coordinator.stageLazyDependency(
            object, owner: owner, attribution: entered.attribution, group: group)
        XCTAssertEqual(selected.events.subscriptions, 1)
    }

    func testLazySyntheticValidationRetainsTheExactTypedSlotUpdateUntilFinish() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let entered = try selected.enterRow(0)
        let group = try XCTUnwrap(entered.attribution.native.registerGroup(kind: .observation))
        let events = LazyListReentryUpdateEvents()
        let identity = entered.context.retainedViewIdentity.appending(
            .view(ObjectIdentifier(LazyListReentryUpdate.self)))

        selected.facade.coordinator.stageOnChange(
            at: identity, attribution: entered.attribution, kind: .onChange, group: group,
            seedObservation: { 0 },
            makeUpdate: { owner, _ in LazyListReentryUpdate(owner: owner, events: events) })

        XCTAssertEqual(events.creations, 1)
        XCTAssertEqual(events.releases, 0, "A valid exact typed slot must retain its staged update")
        selected.close()
        XCTAssertEqual(events.commits, 0)
        XCTAssertEqual(events.deliveries, 0)
        XCTAssertEqual(events.releases, 1)
    }

    func testDescriptorSyntheticValidationRetainsTheExactTypedSlotUpdateUntilFinish() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let context = try fixture.installDescriptorSibling()
        let attribution = try XCTUnwrap(context.viewIdentity.descriptorComponent)
        let group = try XCTUnwrap(attribution.registerGroup(kind: .observation))
        let events = LazyListReentryUpdateEvents()
        let identity = context.retainedViewIdentity.appending(.view(ObjectIdentifier(LazyListReentryUpdate.self)))

        fixture.coordinator.stageOnChange(
            at: identity, descriptorAttribution: attribution, kind: .onChange, group: group,
            seedObservation: { 0 },
            makeUpdate: { owner, _ in LazyListReentryUpdate(owner: owner, events: events) })

        XCTAssertEqual(events.creations, 1)
        XCTAssertEqual(events.releases, 0, "A valid exact typed slot must retain its staged update")
        fixture.close()
        XCTAssertEqual(events.commits, 0)
        XCTAssertEqual(events.deliveries, 0)
        XCTAssertEqual(events.releases, 1)
    }

    func testRejectedStructuralAppendPublishesOnlyAMarkedFailureAfterTheExistingSiblings() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let entered = try selected.enterRow(0)
        let rejectedOutput = ViewNode()
        let originalSibling = ViewNode()
        let component = Component(
            makeViewNode: { _ in rejectedOutput },
            appendStructuralChildren: { _, nodes in
                nodes.append(rejectedOutput)
                entered.attribution.admission.reject()
            })
        let preserved = preservingViewIdentity(of: component, context: entered.context)
        var output = [originalSibling]

        preserved.appendChildNodes(runtime: selected.facade.runtime, to: &output)

        XCTAssertEqual(output.count, 2)
        XCTAssertTrue(output.first === originalSibling)
        XCTAssertFalse(output.contains { $0 === rejectedOutput })
        XCTAssertTrue(try XCTUnwrap(output.last).containsRejectedRetainedSource)
        XCTAssertFalse(entered.attribution.isCurrent)
    }

    func testActualEmptyStructuralOutputRemainsEmptyAndClosesItsExactGroup() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let entered = try selected.enterRow(0)
        let component = Component(makeViewNode: { _ in ViewNode() }, appendStructuralChildren: { _, _ in })
        let preserved = preservingViewIdentity(of: component, context: entered.context)
        var output: [ViewNode] = []

        preserved.appendChildNodes(runtime: selected.facade.runtime, to: &output)

        XCTAssertTrue(output.isEmpty)
        XCTAssertTrue(entered.attribution.isCurrent)
        selected.facade.activity.leaveLazyListMaterialization(entered.attribution.native)
        let preparation = try XCTUnwrap(selected.journal.preparation())
        let group = try XCTUnwrap(preparation.groups.first { $0.component === entered.attribution.component })
        XCTAssertEqual(group.construction, .closedEmpty)
        XCTAssertTrue(group.requiredFacets.isEmpty)
    }

    func testRawLegacyOnChangeRejectsCompositePreparationBeforeNativeMutation() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let update = LazyListReentryUpdateEvents()
        selected.facade.coordinator.stageOnChange(at: selected.facade.context.retainedViewIdentity) { owner in
            LazyListReentryUpdate(owner: owner, events: update)
        }
        let source = ViewNode()
        _ = try XCTUnwrap(selected.journal.registerSourceDescriptor(selected.binding, on: source))
        let preparation = try XCTUnwrap(selected.journal.preparation())
        XCTAssertTrue(selected.journal.hasManagedContributions)

        XCTAssertNil(selected.facade.activity.willAdoptLazyList(preparation))

        XCTAssertFalse(selected.journal.hasAcceptedContributions)
        XCTAssertEqual(update.commits, 0)
        XCTAssertEqual(update.deliveries, 0)
        XCTAssertTrue(selected.facade.target.children.isEmpty)
        withExtendedLifetime(source) {}
    }

    func testRawLegacyDependencyRejectsCompositePreparationBeforeNativeMutation() async throws {
        let selected = try LazyListSelectedReentryFixture()
        defer { selected.close() }
        let object = LazyListReentryObservedObject()
        selected.facade.coordinator.observe(object, at: selected.facade.context.retainedViewIdentity)
        XCTAssertEqual(selected.events.subscriptions, 1)
        let source = ViewNode()
        _ = try XCTUnwrap(selected.journal.registerSourceDescriptor(selected.binding, on: source))
        let preparation = try XCTUnwrap(selected.journal.preparation())

        XCTAssertNil(selected.facade.activity.willAdoptLazyList(preparation))

        XCTAssertFalse(selected.journal.hasAcceptedContributions)
        XCTAssertFalse(selected.facade.coordinator.registry.isClosed)
        XCTAssertEqual(selected.events.subscriptions, 1)
        withExtendedLifetime((source, object)) {}
    }

    func testOrdinaryRawOnChangeStillUsesItsExistingFullAdoptionRoute() async throws {
        let fixture = try LazyListReentryFixture()
        defer { fixture.close() }
        let events = LazyListReentryUpdateEvents()
        fixture.coordinator.stageOnChange(at: fixture.context.retainedViewIdentity) { owner in
            LazyListReentryUpdate(owner: owner, events: events)
        }
        XCTAssertTrue(fixture.build.willAdopt())
        fixture.build.commit()
        XCTAssertEqual(events.commits, 1)
        XCTAssertEqual(events.deliveries, 0)
        fixture.finishCommitted()
        XCTAssertEqual(events.deliveries, 1)
        fixture.build.finishAfterCallbacks()
        XCTAssertEqual(events.deliveries, 1)
    }

    func testPreparationClosesConstructionWithoutRejectingItsOriginalPublicationHandoff() async throws {
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
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        defer {
            journal.revokeBeforeAbandon()
            build.abandon()
            build.finishAfterCallbacks()
            coordinator.close()
            withExtendedLifetime(runtime) {}
        }
        let component = try XCTUnwrap(scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(component.registerGroup(kind: .structure))
        _ = try XCTUnwrap(component.closeGroup(group))
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(component.canConstruct, "Freezing source registration does not revoke the original component")

        let prepared = try XCTUnwrap(activity.willAdoptLazyList(preparation))

        XCTAssertTrue(prepared.preparation === preparation)
        XCTAssertTrue(journal.beginAdoption(preparation, preparedActivity: prepared))
        XCTAssertFalse(component.canConstruct)
        XCTAssertFalse(build.canAdopt)
        XCTAssertFalse(journal.hasAcceptedContributions, "Preparation alone accepts no physical output")
    }
}

@MainActor
private final class LazyListReentryFixture {
    let coordinator: StateMountCoordinator
    let build: any RetainedBuildEpoch
    let activity: any RetainedLazyListBuildActivity
    let scope: RetainedLazyListDescriptorBuildScope
    let target: ViewNode
    let runtime: RetainedViewRuntime
    private let hostLifetime: RetainedLazyListLogicalHostLifetime
    private(set) var context: ViewBuildContext
    private var didFinish = false

    init(
        bindNativeScope: Bool = true,
        onObserved: @escaping @MainActor (any ObservableObject) -> Void = { _ in }
    ) throws {
        let coordinator = StateMountCoordinator(
            invalidate: {}, observeObject: onObserved, updateObservedObjects: { _, _, _ in })
        let build = try XCTUnwrap(coordinator.beginBuild())
        let activity = try XCTUnwrap(build as? any RetainedLazyListBuildActivity)
        let target = ViewNode()
        let runtime = RetainedViewRuntime(root: target)
        let lifetime = runtime.lazyListLogicalHostLifetime
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: lifetime,
            ownerLifetime: target.lazyListActivityStorage().descriptorOwnerLifetime)
        if bindNativeScope { XCTAssertTrue(activity.bindLazyListDescriptorScope(scope)) }
        var context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { Size(width: 320, height: 240) },
            invalidateHandler: {}
        ).withViewIdentityType(LazyListReentryOwner.self)
        _ = try XCTUnwrap(coordinator.install(LazyListReentryOwner(), context: &context))
        self.coordinator = coordinator
        self.build = build
        self.activity = activity
        self.scope = scope
        self.target = target
        self.runtime = runtime
        hostLifetime = lifetime
        self.context = context
    }

    func installSibling() throws -> StateMountOwner {
        var sibling = context.withViewIdentityRole(.content).withViewIdentityType(LazyListReentrySibling.self)
        _ = try XCTUnwrap(coordinator.install(LazyListReentrySibling(), context: &sibling))
        return try XCTUnwrap(sibling.viewIdentity.installedOwner)
    }

    func descriptorContext(hashing gate: LazyListReentryHashGate, value: Int) throws -> ViewBuildContext {
        var descriptor = context.withViewIdentityPrefix([
            .explicit(.init(LazyListReentryHashKey(value: value, gate: gate)))
        ]).withViewIdentityType(LazyListReentryOwner.self)
        _ = try XCTUnwrap(coordinator.install(LazyListReentryOwner(), context: &descriptor))
        return descriptor
    }

    func installDescriptorSibling() throws -> ViewBuildContext {
        let source = context.withViewIdentityRole(.body).withViewIdentityType(LazyListReentrySibling.self)
        var described = try XCTUnwrap(coordinator.contextForDescriptorComponent(from: source))
        _ = try XCTUnwrap(coordinator.install(LazyListReentrySibling(), context: &described))
        return described
    }

    func installPayload(onRelease: @escaping @MainActor () -> Void) throws {
        var payloadContext = context.withViewIdentityRole(.content).withViewIdentityType(LazyListReentryPayload.self)
        let source = LazyListReentryPayload(payload: LazyListReentryReleaseProbe(onRelease: onRelease))
        _ = try XCTUnwrap(coordinator.install(source, context: &payloadContext))
    }

    func finishCommitted() {
        guard !didFinish else { return }
        didFinish = true
        build.finishAfterCallbacks()
    }

    func abandon() {
        guard !didFinish else { return }
        didFinish = true
        build.abandon()
        build.finishAfterCallbacks()
    }

    func close() {
        coordinator.close()
        abandon()
    }
}

private struct LazyListReentryOwner {}
private struct LazyListReentrySibling {}

@MainActor
private struct LazyListReentryPayload {
    @State var payload: LazyListReentryReleaseProbe
}

@MainActor
private final class LazyListReentryReleaseProbe {
    private let onRelease: @MainActor () -> Void
    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

@MainActor
private final class LazyListReentryEvents {
    var releases = 0
    var factoryCalls = 0
    var subscriptions = 0
    var constructionAtRelease: [Bool] = []
    var publicationAtRelease: [Bool] = []
}

@MainActor
private final class LazyListSelectedReentryFixture {
    let facade: LazyListReentryFixture
    let gate: LazyListReentryHashGate
    let events: LazyListReentryEvents
    let provider: RetainedLazyListDataSource<LazyListReentryRow, [ViewNode]>
    let proposal: LazyListMembershipProposal
    let binding: RetainedLazyListManagedLogicalDescriptorBinding
    let adapter: RetainedLazyListRuntimeAdapter
    let nativeCoordinator: RetainedBuildCoordinator
    let admission: RetainedLazyListAdoptionAdmission
    let journal: RetainedLazyListAdoptionJournal
    private let lease: LazyListReentryNativeLease
    private var didClose = false

    init() throws {
        let gate = LazyListReentryHashGate()
        let lease = LazyListReentryNativeLease()
        let events = LazyListReentryEvents()
        let facade = try LazyListReentryFixture(onObserved: { _ in events.subscriptions += 1 })
        let provider = RetainedLazyListDataSource<LazyListReentryRow, [ViewNode]>()
        let receipt = try XCTUnwrap(facade.coordinator.descriptorResolutionReceipt(in: facade.context))
        let identity = facade.context.retainedViewIdentity.appending(.role(.content))
        let rows = [0, 1].map { LazyListReentryRow(id: LazyListReentryHashKey(value: $0, gate: gate)) }
        XCTAssertTrue(
            provider.replaceData(
                rows, id: \.id, identityRoot: identity, descriptorBuildScope: receipt.nativeScope,
                rowContent: { _, _ in
                    events.factoryCalls += 1
                    return []
                }))
        let metadata = try XCTUnwrap(provider.metadata)
        let proposal = try XCTUnwrap(
            facade.coordinator.stageLazyMembership(
                at: identity, metadata: metadata, context: facade.context, receipt: receipt))
        let binding = proposal.nativeBinding
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        XCTAssertTrue(adapter.installManagedLogicalDescriptor(binding))
        facade.target.retainedSubtreeBuildLease = lease
        facade.target.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.claimAttachment(to: facade.target))
        let nativeCoordinator = RetainedBuildCoordinator()
        let sequence = try XCTUnwrap(nativeCoordinator.beginBuild())
        nativeCoordinator.install(facade.build, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: facade.target, runtime: facade.runtime,
            coordinator: nativeCoordinator, sequence: sequence)
        XCTAssertTrue(admission.isBuildCurrent)
        let journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: RetainedBuildTransaction())
        XCTAssertTrue(journal.bindDescriptorScope(facade.scope))
        self.facade = facade
        self.gate = gate
        self.lease = lease
        self.events = events
        self.provider = provider
        self.proposal = proposal
        self.binding = binding
        self.adapter = adapter
        self.nativeCoordinator = nativeCoordinator
        self.admission = admission
        self.journal = journal
    }

    func prepareRow(_ index: Int) throws -> RetainedLazyListSelectedRowPreparation {
        let metadata = try XCTUnwrap(provider.metadata)
        let request = try XCTUnwrap(provider.request(for: metadata.rows[index].token))
        return try XCTUnwrap(journal.prepareSelectedRow(request: request, descriptor: binding))
    }

    func enterRow(_ index: Int) throws -> (context: ViewBuildContext, attribution: LazyListViewAttribution) {
        let preparation = try prepareRow(index)
        let response = try XCTUnwrap(facade.activity.resolveSelectedLazyListRow(preparation))
        let native = try XCTUnwrap(journal.consumeSelectedRowResolution(response, for: preparation))
        XCTAssertTrue(facade.activity.enterLazyListMaterialization(native))
        var context = try XCTUnwrap(
            facade.coordinator.contextForEnteredLazyRow(from: facade.context, descriptor: binding))
        context.viewIdentity.path = try XCTUnwrap(provider.identityPrefix(for: preparation.request))
        return (context, try XCTUnwrap(context.viewIdentity.lazyList))
    }

    func close() {
        guard !didClose else { return }
        didClose = true
        gate.disarm()
        journal.revokeBeforeAbandon()
        admission.revoke()
        facade.close()
        provider.close()
        nativeCoordinator.finishBuild()
    }
}

private struct LazyListReentryRow {
    let id: LazyListReentryHashKey
}

@MainActor
private final class LazyListReentryNativeLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { nil }
}

@MainActor
private final class LazyListReentryObservedObject: ObservableObject {}

@MainActor
private final class LazyListReentryUpdateEvents {
    var creations = 0
    var releases = 0
    var commits = 0
    var deliveries = 0
}

@MainActor
private final class LazyListReentryUpdate: MountedOnChangeUpdate {
    let owner: StateMountOwner
    let events: LazyListReentryUpdateEvents
    init(owner: StateMountOwner, events: LazyListReentryUpdateEvents) {
        self.owner = owner
        self.events = events
        events.creations += 1
    }
    func commit() { events.commits += 1 }
    func deliver() { events.deliveries += 1 }
    isolated deinit { events.releases += 1 }
}

@MainActor
private final class LazyListReentryHashGate {
    private var action: (@MainActor () -> Void)?
    private(set) var firings = 0

    func arm(_ action: @escaping @MainActor () -> Void) {
        firings = 0
        self.action = action
    }

    func disarm() { action = nil }

    func fire() {
        guard let action else { return }
        self.action = nil
        firings += 1
        action()
    }
}

private struct LazyListReentryHashKey: Hashable {
    let value: Int
    let gate: LazyListReentryHashGate

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        MainActor.assumeIsolated { gate.fire() }
    }
}
