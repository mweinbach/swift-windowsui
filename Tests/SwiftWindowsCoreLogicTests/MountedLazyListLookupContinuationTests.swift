import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedLazyListLookupContinuationTests: XCTestCase {
    func testProviderInvalidationAtFirstDescriptorHashSkipsLaterIdentityAndMetadataKeys() async throws {
        let fixture = try MountedLookupContinuationFixture()
        let events = MountedLookupContinuationEvents()
        let provider = RetainedLazyListDataSource<MountedLookupContinuationRow, Int>()
        defer {
            events.disarm()
            provider.close()
            fixture.close()
        }
        var context = fixture.context.withViewIdentityPrefix([
            .explicit(key("descriptor.first", value: 1, events: events)),
            .explicit(key("descriptor.second", value: 2, events: events)),
        ]).withViewIdentityType(MountedLookupContinuationRoot.self)
        _ = try XCTUnwrap(fixture.coordinator.install(MountedLookupContinuationRoot(), context: &context))
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: context))
        XCTAssertTrue(
            provider.replaceData(metadataRows(events: events), id: \.id) { _ in
                events.rowFactories += 1
                return 0
            })
        let metadata = try XCTUnwrap(provider.metadata)
        events.arm(on: "hash:descriptor.first") { provider.close() }

        let result = fixture.coordinator.stageLazyMembership(
            at: context.retainedViewIdentity, metadata: metadata, context: context, receipt: receipt)

        events.disarm()
        XCTAssertNil(result)
        XCTAssertEqual(events.callbacks, ["hash:descriptor.first"])
        XCTAssertTrue(events.callbacksAfterHook.isEmpty)
        XCTAssertEqual(events.hookCalls, 1)
        XCTAssertFalse(metadata.generation.isCurrent)
        XCTAssertTrue(receipt.isCurrent, "The descriptor is still open; only its source generation was revoked")
        XCTAssertTrue(fixture.scope.canConstructDescriptors)
        XCTAssertEqual(events.rowFactories, 0)
    }

    func testProviderInvalidationAtFirstRetainedRowHashSkipsLaterNestedKeysAndMetadataRows() async throws {
        let fixture = try MountedLookupContinuationFixture()
        let events = MountedLookupContinuationEvents()
        let provider = RetainedLazyListDataSource<MountedLookupContinuationRow, Int>()
        defer {
            events.disarm()
            provider.close()
            fixture.close()
        }
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        XCTAssertTrue(
            provider.replaceData(metadataRows(events: events), id: \.id) { _ in
                events.rowFactories += 1
                return 0
            })
        let metadata = try XCTUnwrap(provider.metadata)
        let identity = fixture.context.retainedViewIdentity.appending(.role(.content))
        events.arm(on: "hash:row.first") { provider.close() }

        let result = fixture.coordinator.stageLazyMembership(
            at: identity, metadata: metadata, context: fixture.context, receipt: receipt)

        events.disarm()
        XCTAssertNil(result)
        XCTAssertEqual(events.callbacks, ["hash:row.first"])
        XCTAssertTrue(events.callbacksAfterHook.isEmpty)
        XCTAssertEqual(events.hookCalls, 1)
        XCTAssertFalse(metadata.generation.isCurrent)
        XCTAssertTrue(receipt.isCurrent)
        XCTAssertTrue(fixture.scope.canConstructDescriptors)
        XCTAssertEqual(events.rowFactories, 0)
    }

    func testDescriptorOwnerHashReentryRejectsOuterSeedAndPreservesNestedState() async throws {
        try assertOwnerReentry(mode: .descriptor, site: .hash)
    }

    func testDescriptorOwnerCollisionEqualityReentryRejectsOuterSeedAndPreservesNestedState() async throws {
        try assertOwnerReentry(mode: .descriptor, site: .collisionEquality)
    }

    func testDescriptorOwnerScopeEqualityCannotRenewItsOriginalLookupAfterReentry() async throws {
        try assertOwnerReentry(mode: .descriptor, site: .scopeEquality)
    }

    func testLazyOwnerHashReentryRejectsOuterSeedAndPreservesNestedState() async throws {
        try assertOwnerReentry(mode: .lazy, site: .hash)
    }

    func testLazyOwnerCollisionEqualityReentryRejectsOuterSeedAndPreservesNestedState() async throws {
        try assertOwnerReentry(mode: .lazy, site: .collisionEquality)
    }

    func testLazyOwnerScopeEqualityCannotRenewItsOriginalLookupAfterReentry() async throws {
        try assertOwnerReentry(mode: .lazy, site: .scopeEquality)
    }

    func testDescriptorOwnerCanAdvanceItsOwnLookupAndInstallItsSeed() async throws {
        try assertSuccessfulOwnerInstallation(mode: .descriptor)
    }

    func testLazyOwnerCanAdvanceItsOwnLookupAndInstallItsSeed() async throws {
        try assertSuccessfulOwnerInstallation(mode: .lazy)
    }

    func testConvenienceOccurrencesInheritDescriptorContextAndStopAtFirstReentrantHash() async throws {
        try assertContextualOccurrences(mode: .descriptor)
    }

    func testConvenienceOccurrencesInheritLazyContextAndStopAtFirstReentrantHash() async throws {
        try assertContextualOccurrences(mode: .lazy)
    }

    func testDescriptorObserverScopeEqualityCannotRenewLookupAfterOrdinaryStateReentry() async throws {
        try assertObserverScopeReentry(mode: .descriptor)
    }

    func testLazyObserverScopeEqualityCannotRenewLookupAfterOrdinaryStateReentry() async throws {
        try assertObserverScopeReentry(mode: .lazy)
    }

    func testDescriptorUpdateFactoryReentryKeepsInnerUpdateAndReleasesStaleOuterUpdate() async throws {
        try assertObserverUpdateReentry(mode: .descriptor)
    }

    func testLazyUpdateFactoryReentryKeepsInnerUpdateAndReleasesStaleOuterUpdate() async throws {
        try assertObserverUpdateReentry(mode: .lazy)
    }

    private func assertObserverScopeReentry(
        mode: MountedLookupContinuationMode, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try MountedLookupContinuationFixture()
        let events = MountedLookupContinuationEvents()
        let selected = try selection(mode: mode, fixture: fixture, events: events)
        defer {
            events.disarm()
            selected?.close()
            fixture.close()
        }
        let (context, route) = try observerRoute(mode: mode, fixture: fixture, selected: selected)
        let identity = context.retainedViewIdentity.appending(contentsOf: [
            .explicit(key("observer.first", value: 1, events: events)),
            .explicit(key("observer.second", value: 2, events: events)),
            .view(ObjectIdentifier(MountedLookupContinuationObserverMarker.self)),
        ])
        let discardPrefix = context.retainedViewIdentity.appending(contentsOf: [
            .explicit(key("discard.first", value: 41, events: events)),
            .explicit(key("discard.second", value: 42, events: events)),
        ])
        var seeds = 0
        var updates = 0
        var cleanupCalls = 0
        var discardReturned = false
        var cleanupWasInsideDiscard = false
        var attributionSurvivedNestedInstallation = false
        var originalLookup: LazyListLookupReceipt?
        var nested: MountedLookupContinuationInstalledState?
        let victim = try installDiscardPayload(
            at: discardPrefix.appending(.role(.overlay)), in: fixture.epoch,
            onRelease: {
                cleanupCalls += 1
                cleanupWasInsideDiscard = !discardReturned
                originalLookup = route.lookup(in: fixture.coordinator)
                events.arm(on: "equal:observer.first:discard.first") {
                    nested = try? fixture.installOrdinarySibling()
                    attributionSurvivedNestedInstallation = route.isCurrent
                }
                route.stage(
                    at: identity, in: fixture.coordinator,
                    seed: {
                        seeds += 1
                        return 0
                    },
                    makeUpdate: { _, _ in
                        updates += 1
                        return nil
                    })
                events.disarm()
            })
        XCTAssertNotNil(victim.payload, file: file, line: line)

        fixture.coordinator.discardUnadoptedSubtree(at: discardPrefix, preserveCommitted: false)

        discardReturned = true
        XCTAssertEqual(cleanupCalls, 1, file: file, line: line)
        XCTAssertTrue(
            cleanupWasInsideDiscard, "The observer must enter while the discard scope is active", file: file, line: line
        )
        XCTAssertNil(victim.payload, file: file, line: line)
        XCTAssertNil(victim.cell, file: file, line: line)
        XCTAssertNil(victim.owner, file: file, line: line)
        XCTAssertEqual(events.callbacks, ["equal:observer.first:discard.first"], file: file, line: line)
        XCTAssertTrue(events.callbacksAfterHook.isEmpty, file: file, line: line)
        XCTAssertEqual(events.hookCalls, 1, file: file, line: line)
        XCTAssertTrue(
            attributionSurvivedNestedInstallation,
            "A still-valid native attribution cannot renew the interrupted lookup", file: file, line: line)
        XCTAssertFalse(try XCTUnwrap(originalLookup, file: file, line: line).isCurrent, file: file, line: line)
        XCTAssertEqual(seeds, 0, file: file, line: line)
        XCTAssertEqual(updates, 0, file: file, line: line)
        XCTAssertFalse(fixture.epoch.visitedOwnerIdentities.contains(identity), file: file, line: line)
        XCTAssertTrue(fixture.build.canAdopt, file: file, line: line)
        try assertNestedState(nested, in: fixture, file: file, line: line)
        XCTAssertEqual(events.rowFactories, 0, file: file, line: line)
    }

    private func assertObserverUpdateReentry(
        mode: MountedLookupContinuationMode, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try MountedLookupContinuationFixture()
        let events = MountedLookupContinuationEvents()
        let updates = MountedLookupContinuationUpdateEvents()
        let selected = try selection(mode: mode, fixture: fixture, events: events)
        defer {
            selected?.close()
            fixture.close()
        }
        let (context, route) = try observerRoute(mode: mode, fixture: fixture, selected: selected)
        let identity = context.retainedViewIdentity.appending(
            .view(ObjectIdentifier(MountedLookupContinuationObserverMarker.self)))
        var outerSeeds = 0
        var innerSeeds = 0
        var innerCell: MountedStateCell<Int>?
        var lookupBeforeNestedUpdate: LazyListLookupReceipt?

        route.stage(
            at: identity, in: fixture.coordinator,
            seed: {
                outerSeeds += 1
                return 7
            },
            makeUpdate: { owner, outerCell in
                let outer = updates.make(owner: owner, label: "outer")
                lookupBeforeNestedUpdate = route.lookup(in: fixture.coordinator)
                route.stage(
                    at: identity, in: fixture.coordinator,
                    seed: {
                        innerSeeds += 1
                        return 99
                    },
                    makeUpdate: { nestedOwner, cell in
                        XCTAssertTrue(nestedOwner === owner, file: file, line: line)
                        XCTAssertTrue(cell === outerCell, file: file, line: line)
                        innerCell = cell
                        return updates.make(owner: nestedOwner, label: "inner")
                    })
                return outer
            })

        XCTAssertEqual(outerSeeds, 1, file: file, line: line)
        XCTAssertEqual(innerSeeds, 0, "The nested observer reuses its exact synthetic cell", file: file, line: line)
        XCTAssertEqual(updates.made, ["outer", "inner"], file: file, line: line)
        XCTAssertEqual(
            updates.released, ["outer"],
            "The stale outer update must not displace or retain itself over the inner update", file: file, line: line)
        XCTAssertNil(updates.outer, file: file, line: line)
        let innerOwner = try XCTUnwrap(updates.inner?.owner, file: file, line: line)
        XCTAssertTrue(innerOwner.isInstallationActive, file: file, line: line)
        XCTAssertTrue(fixture.epoch.visitedOwnerIdentities.contains(innerOwner.identity), file: file, line: line)
        XCTAssertFalse(
            try XCTUnwrap(lookupBeforeNestedUpdate, file: file, line: line).isCurrent, file: file, line: line)
        XCTAssertTrue(
            route.isCurrent, "The inner update retains its original framework attribution", file: file, line: line)
        let cell = try XCTUnwrap(innerCell, file: file, line: line)
        XCTAssertEqual(cell.readValue(), 7, file: file, line: line)
        XCTAssertTrue(cell.isWritable, file: file, line: line)
        XCTAssertTrue(cell.write(71), file: file, line: line)
        XCTAssertEqual(cell.readValue(), 71, file: file, line: line)
        XCTAssertTrue(updates.committed.isEmpty, file: file, line: line)
        XCTAssertTrue(updates.delivered.isEmpty, file: file, line: line)
        XCTAssertEqual(events.rowFactories, 0, file: file, line: line)

        selected?.close()
        fixture.close()
        XCTAssertNil(updates.inner, file: file, line: line)
        XCTAssertEqual(updates.released, ["outer", "inner"], file: file, line: line)
        XCTAssertTrue(updates.committed.isEmpty, file: file, line: line)
        XCTAssertTrue(updates.delivered.isEmpty, file: file, line: line)
    }

    private func observerRoute(
        mode: MountedLookupContinuationMode, fixture: MountedLookupContinuationFixture,
        selected: MountedLookupContinuationSelection?
    ) throws -> (ViewBuildContext, MountedLookupContinuationObserverRoute) {
        switch mode {
        case .descriptor:
            let base = fixture.context.withViewIdentityRole(.body).withViewIdentityType(
                MountedLookupContinuationRoot.self)
            var context = try XCTUnwrap(fixture.coordinator.contextForDescriptorComponent(from: base))
            _ = try XCTUnwrap(fixture.coordinator.install(MountedLookupContinuationRoot(), context: &context))
            let attribution = try XCTUnwrap(context.viewIdentity.descriptorComponent)
            let group = try XCTUnwrap(attribution.registerGroup(kind: .observation))
            return (context, .descriptor(attribution, group))
        case .lazy:
            let context = try XCTUnwrap(selected).enterRow()
            let attribution = try XCTUnwrap(context.viewIdentity.lazyList)
            let group = try XCTUnwrap(attribution.native.registerGroup(kind: .observation))
            return (context, .lazy(attribution, group))
        }
    }

    @inline(never)
    private func installDiscardPayload(
        at identity: RetainedViewIdentity, in epoch: StateMountEpoch, onRelease: @escaping @MainActor () -> Void
    ) throws -> MountedLookupContinuationWeakPayload {
        let owner = try XCTUnwrap(epoch.owner(at: identity))
        let payload = MountedLookupContinuationReleasePayload(onRelease: onRelease)
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(MountedLookupContinuationReleasePayload.self)])
        let cell = owner.resolve(at: slot) { payload }
        return MountedLookupContinuationWeakPayload(owner: owner, cell: cell, payload: payload)
    }

    private func assertOwnerReentry(
        mode: MountedLookupContinuationMode, site: MountedLookupContinuationSite,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try MountedLookupContinuationFixture()
        let events = MountedLookupContinuationEvents()
        let selected = try selection(mode: mode, fixture: fixture, events: events)
        defer {
            events.disarm()
            selected?.close()
            fixture.close()
        }
        let base = try selected?.enterRow() ?? fixture.context
        var context = try ownerContext(base: base, mode: mode, fixture: fixture, events: events)
        var storedOwner: StateMountOwner?
        if site == .collisionEquality {
            var stored = base.withViewIdentityRole(.body).withViewIdentityPrefix([
                .explicit(key("stored.first", value: 1, events: events)),
                .explicit(key("stored.second", value: 99, events: events)),
            ]).withViewIdentityType(MountedLookupContinuationSeedOwner.self)
            stored.viewIdentity.lazyList = nil
            stored.viewIdentity.descriptorComponent = nil
            _ = try XCTUnwrap(
                fixture.coordinator.install(MountedLookupContinuationSeedOwner(events: events), context: &stored))
            storedOwner = try XCTUnwrap(stored.viewIdentity.installedOwner)
        }
        var discard: LazyListDiscardReceipt?
        if site == .scopeEquality {
            let prefix = base.withViewIdentityRole(.body).withViewIdentityPrefix([
                .explicit(key("scope.first", value: 42, events: events)),
                .explicit(key("scope.second", value: 43, events: events)),
            ]).retainedViewIdentity
            switch mode {
            case .descriptor:
                discard = try XCTUnwrap(
                    fixture.epoch.discardDescriptorSubtree(
                        at: prefix, preserveCommitted: false,
                        attribution: try XCTUnwrap(context.viewIdentity.descriptorComponent)))
            case .lazy:
                discard = try XCTUnwrap(fixture.epoch.discardLazySubtree(at: prefix, preserveCommitted: false))
            }
        }
        defer { if let discard { fixture.epoch.finishLazyDiscardScope(discard) } }
        let seedCount = events.objectSeeds
        let expected: [String]
        switch site {
        case .hash:
            expected = ["hash:outer.first"]
        case .collisionEquality:
            expected = ["hash:outer.first", "hash:outer.second", "equal:stored.first:outer.first"]
        case .scopeEquality:
            expected = ["equal:outer.first:scope.first"]
        }
        var nested: MountedLookupContinuationInstalledState?
        events.arm(on: try XCTUnwrap(expected.last)) { nested = try? fixture.installOrdinarySibling() }

        let result = fixture.coordinator.install(MountedLookupContinuationSeedOwner(events: events), context: &context)

        events.disarm()
        XCTAssertNil(
            result, "A rejected owner lookup must not reach dynamic property installation", file: file, line: line)
        XCTAssertEqual(events.callbacks, expected, file: file, line: line)
        XCTAssertTrue(events.callbacksAfterHook.isEmpty, file: file, line: line)
        XCTAssertEqual(events.hookCalls, 1, file: file, line: line)
        XCTAssertEqual(
            events.objectSeeds, seedCount, "The interrupted owner's seed must not run", file: file, line: line)
        XCTAssertNil(context.viewIdentity.installedOwner, file: file, line: line)
        XCTAssertFalse(
            fixture.epoch.visitedOwnerIdentities.contains(context.retainedViewIdentity), file: file, line: line)
        XCTAssertTrue(
            fixture.build.canAdopt, "Unrelated installation must not supersede the whole epoch", file: file, line: line)
        if let storedOwner { XCTAssertTrue(storedOwner.isInstallationActive, file: file, line: line) }
        try assertNestedState(nested, in: fixture, file: file, line: line)
        XCTAssertEqual(events.rowFactories, 0, file: file, line: line)
    }

    private func assertSuccessfulOwnerInstallation(
        mode: MountedLookupContinuationMode, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try MountedLookupContinuationFixture()
        let events = MountedLookupContinuationEvents()
        let selected = try selection(mode: mode, fixture: fixture, events: events)
        defer {
            events.disarm()
            selected?.close()
            fixture.close()
        }
        let base = try selected?.enterRow() ?? fixture.context
        var context = try ownerContext(base: base, mode: mode, fixture: fixture, events: events)
        events.arm()

        let installed = try XCTUnwrap(
            fixture.coordinator.install(MountedLookupContinuationSeedOwner(events: events), context: &context),
            file: file, line: line)

        events.disarm()
        let owner = try XCTUnwrap(context.viewIdentity.installedOwner, file: file, line: line)
        XCTAssertTrue(owner.isInstallationActive, file: file, line: line)
        XCTAssertTrue(context.viewIdentity.installedEpoch === fixture.epoch, file: file, line: line)
        XCTAssertEqual(events.objectSeeds, 1, file: file, line: line)
        XCTAssertTrue(installed.model.events === events, file: file, line: line)
        XCTAssertTrue(events.callbacks.contains("hash:outer.first"), file: file, line: line)
        XCTAssertTrue(events.callbacks.contains("hash:outer.second"), file: file, line: line)
        XCTAssertEqual(events.hookCalls, 0, file: file, line: line)
        XCTAssertEqual(events.rowFactories, 0, file: file, line: line)
        switch mode {
        case .descriptor:
            XCTAssertTrue(try XCTUnwrap(context.viewIdentity.descriptorComponent).canConstruct, file: file, line: line)
        case .lazy:
            XCTAssertTrue(try XCTUnwrap(context.viewIdentity.lazyList).isCurrent, file: file, line: line)
        }
    }

    private func assertContextualOccurrences(
        mode: MountedLookupContinuationMode, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try MountedLookupContinuationFixture()
        let events = MountedLookupContinuationEvents()
        let selected = try selection(mode: mode, fixture: fixture, events: events)
        defer {
            events.disarm()
            selected?.close()
            fixture.close()
        }
        let context: ViewBuildContext
        switch mode {
        case .descriptor:
            let base = fixture.context.withViewIdentityRole(.body).withViewIdentityType(
                MountedLookupContinuationRoot.self)
            var described = try XCTUnwrap(fixture.coordinator.contextForDescriptorComponent(from: base))
            _ = try XCTUnwrap(fixture.coordinator.install(MountedLookupContinuationRoot(), context: &described))
            context = described
        case .lazy:
            context = try XCTUnwrap(selected).enterRow()
        }
        let views = [
            AnyView(EmptyView()).prefixedViewIdentity([
                .explicit(key("fragment.first", value: 1, events: events)),
                .explicit(key("fragment.second", value: 2, events: events)),
            ]),
            AnyView(EmptyView()).prefixedViewIdentity([
                .explicit(key("later.fragment", value: 3, events: events))
            ]),
        ]
        var nested: MountedLookupContinuationInstalledState?
        events.arm(on: "hash:fragment.first") { nested = try? fixture.installOrdinarySibling() }

        let result = ViewBuildContextScope.withCurrent(context) { viewIdentityOccurrences(views) }

        events.disarm()
        XCTAssertTrue(
            result.isEmpty, "The convenience entry must inherit managed lookup rejection", file: file, line: line)
        XCTAssertEqual(events.callbacks, ["hash:fragment.first"], file: file, line: line)
        XCTAssertTrue(events.callbacksAfterHook.isEmpty, file: file, line: line)
        XCTAssertEqual(events.hookCalls, 1, file: file, line: line)
        switch mode {
        case .descriptor:
            XCTAssertFalse(try XCTUnwrap(context.viewIdentity.descriptorComponent).canConstruct, file: file, line: line)
        case .lazy:
            XCTAssertFalse(try XCTUnwrap(context.viewIdentity.lazyList).isCurrent, file: file, line: line)
        }
        XCTAssertTrue(fixture.build.canAdopt, file: file, line: line)
        try assertNestedState(nested, in: fixture, file: file, line: line)
        XCTAssertEqual(events.rowFactories, 0, file: file, line: line)
    }

    private func assertNestedState(
        _ value: MountedLookupContinuationInstalledState?, in fixture: MountedLookupContinuationFixture,
        file: StaticString, line: UInt
    ) throws {
        let nested = try XCTUnwrap(value, file: file, line: line)
        XCTAssertTrue(nested.owner.isInstallationActive, file: file, line: line)
        XCTAssertTrue(nested.epoch === fixture.epoch, file: file, line: line)
        XCTAssertTrue(fixture.epoch.visitedOwnerIdentities.contains(nested.owner.identity), file: file, line: line)
        XCTAssertEqual(nested.value.wrappedValue, 23, file: file, line: line)
        nested.value.wrappedValue = 71
        XCTAssertEqual(
            nested.value.wrappedValue, 71, "Nested State stays writable in its original epoch", file: file, line: line)
    }

    private func ownerContext(
        base: ViewBuildContext, mode: MountedLookupContinuationMode, fixture: MountedLookupContinuationFixture,
        events: MountedLookupContinuationEvents
    ) throws -> ViewBuildContext {
        let context = base.withViewIdentityRole(.body).withViewIdentityPrefix([
            .explicit(key("outer.first", value: 1, events: events)),
            .explicit(key("outer.second", value: 2, events: events)),
        ]).withViewIdentityType(MountedLookupContinuationSeedOwner.self)
        switch mode {
        case .descriptor:
            return try XCTUnwrap(fixture.coordinator.contextForDescriptorComponent(from: context))
        case .lazy:
            return context
        }
    }

    private func selection(
        mode: MountedLookupContinuationMode, fixture: MountedLookupContinuationFixture,
        events: MountedLookupContinuationEvents
    ) throws -> MountedLookupContinuationSelection? {
        switch mode {
        case .descriptor: return nil
        case .lazy: return try MountedLookupContinuationSelection(fixture: fixture, events: events)
        }
    }

    private func key(
        _ label: String, value: Int, events: MountedLookupContinuationEvents
    ) -> RetainedViewIdentity.Key {
        .init(MountedLookupContinuationKey(label: label, value: value, events: events))
    }

    private func metadataRows(events: MountedLookupContinuationEvents) -> [MountedLookupContinuationRow] {
        [
            MountedLookupContinuationRow(
                id: RetainedViewIdentity(segments: [
                    .keyed(key("row.first", value: 1, events: events)),
                    .keyed(key("row.second", value: 2, events: events)),
                ])),
            MountedLookupContinuationRow(
                id: RetainedViewIdentity(segments: [
                    .keyed(key("later.row", value: 3, events: events))
                ])),
        ]
    }
}

@MainActor
private final class MountedLookupContinuationFixture {
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
            stateMountCoordinator: coordinator, canvasSizeProvider: { Size(width: 320, height: 240) },
            invalidateHandler: {}
        ).withViewIdentityType(MountedLookupContinuationRoot.self)
        _ = try XCTUnwrap(coordinator.install(MountedLookupContinuationRoot(), context: &context))
        self.coordinator = coordinator
        self.build = build
        self.epoch = try XCTUnwrap(context.viewIdentity.installedEpoch)
        self.activity = activity
        self.scope = scope
        self.target = target
        self.runtime = runtime
        self.context = context
    }

    func installOrdinarySibling() throws -> MountedLookupContinuationInstalledState {
        var sibling = context.withViewIdentityRole(.content).withViewIdentityType(
            MountedLookupContinuationStateOwner.self)
        let installed = try XCTUnwrap(coordinator.install(MountedLookupContinuationStateOwner(), context: &sibling))
        return MountedLookupContinuationInstalledState(
            owner: try XCTUnwrap(sibling.viewIdentity.installedOwner),
            epoch: try XCTUnwrap(sibling.viewIdentity.installedEpoch), value: installed.$value)
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
private final class MountedLookupContinuationSelection {
    let fixture: MountedLookupContinuationFixture
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let binding: RetainedLazyListManagedLogicalDescriptorBinding
    let adapter: RetainedLazyListRuntimeAdapter
    let nativeCoordinator: RetainedBuildCoordinator
    let admission: RetainedLazyListAdoptionAdmission
    let journal: RetainedLazyListAdoptionJournal
    private let lease: MountedLookupContinuationLease
    private var isClosed = false

    init(fixture: MountedLookupContinuationFixture, events: MountedLookupContinuationEvents) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        let receipt = try XCTUnwrap(fixture.coordinator.descriptorResolutionReceipt(in: fixture.context))
        let identity = fixture.context.retainedViewIdentity.appending(.role(.content))
        XCTAssertTrue(
            provider.replaceData(
                [0], id: \.self, identityRoot: identity, descriptorBuildScope: fixture.scope,
                rowContent: { _, _ in
                    events.rowFactories += 1
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
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        XCTAssertTrue(adapter.installManagedLogicalDescriptor(binding))
        let lease = MountedLookupContinuationLease()
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
        XCTAssertTrue(try XCTUnwrap(context.viewIdentity.lazyList).isCurrent)
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

@MainActor
private final class MountedLookupContinuationEvents {
    var rowFactories = 0
    var objectSeeds = 0
    private(set) var callbacks: [String] = []
    private(set) var callbacksAfterHook: [String] = []
    private(set) var hookCalls = 0
    private var isRecording = false
    private var trigger: String?
    private var hook: (@MainActor () -> Void)?

    func arm(on trigger: String? = nil, _ hook: (@MainActor () -> Void)? = nil) {
        callbacks = []
        callbacksAfterHook = []
        hookCalls = 0
        isRecording = true
        self.trigger = trigger
        self.hook = hook
    }

    func disarm() {
        isRecording = false
        hook = nil
    }

    func record(_ callback: String) {
        guard isRecording else { return }
        callbacks.append(callback)
        if hookCalls != 0 { callbacksAfterHook.append(callback) }
        guard callback == trigger, let action = hook else { return }
        hook = nil
        hookCalls += 1
        action()
    }
}

// The witnesses remain nonisolated; these fixtures only invoke them on the
// main actor. Labels record traversal, while equal values hash identically.
private struct MountedLookupContinuationKey: Hashable {
    let label: String
    let value: Int
    let events: MountedLookupContinuationEvents

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.events.record("equal:\(lhs.label):\(rhs.label)") }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
        MainActor.assumeIsolated { events.record("hash:\(label)") }
    }
}

private struct MountedLookupContinuationRow {
    let id: RetainedViewIdentity
}

private struct MountedLookupContinuationRoot {}

private struct MountedLookupContinuationObserverMarker {}

@MainActor
private enum MountedLookupContinuationObserverRoute {
    case descriptor(RetainedDescriptorComponentAttribution, RetainedDescriptorGroupID)
    case lazy(LazyListViewAttribution, RetainedLazyListGroupID)

    var isCurrent: Bool {
        switch self {
        case .descriptor(let attribution, _): return attribution.canConstruct
        case .lazy(let attribution, _): return attribution.isCurrent
        }
    }

    func lookup(in coordinator: StateMountCoordinator) -> LazyListLookupReceipt? {
        switch self {
        case .descriptor(let attribution, _): return coordinator.descriptorLookupReceipt(for: attribution)
        case .lazy(let attribution, _): return attribution.admission.beginLookup()
        }
    }

    func stage(
        at identity: RetainedViewIdentity, in coordinator: StateMountCoordinator, seed: () -> Int,
        makeUpdate: (StateMountOwner, MountedStateCell<Int>) -> (any MountedOnChangeUpdate)?
    ) {
        switch self {
        case .descriptor(let attribution, let group):
            coordinator.stageOnChange(
                at: identity, descriptorAttribution: attribution, kind: .onChange, group: group,
                seedObservation: seed, makeUpdate: makeUpdate)
        case .lazy(let attribution, let group):
            coordinator.stageOnChange(
                at: identity, attribution: attribution, kind: .onChange, group: group,
                seedObservation: seed, makeUpdate: makeUpdate)
        }
    }
}

@MainActor
private final class MountedLookupContinuationReleasePayload {
    let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private final class MountedLookupContinuationWeakPayload {
    weak var owner: StateMountOwner?
    weak var cell: MountedStateCell<MountedLookupContinuationReleasePayload>?
    weak var payload: MountedLookupContinuationReleasePayload?

    init(
        owner: StateMountOwner, cell: MountedStateCell<MountedLookupContinuationReleasePayload>,
        payload: MountedLookupContinuationReleasePayload
    ) {
        self.owner = owner
        self.cell = cell
        self.payload = payload
    }
}

@MainActor
private final class MountedLookupContinuationUpdateEvents {
    var made: [String] = []
    var released: [String] = []
    var committed: [String] = []
    var delivered: [String] = []
    weak var outer: MountedLookupContinuationUpdate?
    weak var inner: MountedLookupContinuationUpdate?

    func make(owner: StateMountOwner, label: String) -> MountedLookupContinuationUpdate {
        let update = MountedLookupContinuationUpdate(owner: owner, label: label, events: self)
        made.append(label)
        if label == "outer" { outer = update } else { inner = update }
        return update
    }
}

@MainActor
private final class MountedLookupContinuationUpdate: MountedOnChangeUpdate {
    let owner: StateMountOwner
    let label: String
    let events: MountedLookupContinuationUpdateEvents

    init(owner: StateMountOwner, label: String, events: MountedLookupContinuationUpdateEvents) {
        self.owner = owner
        self.label = label
        self.events = events
    }

    func commit() { events.committed.append(label) }
    func deliver() { events.delivered.append(label) }
    isolated deinit { events.released.append(label) }
}

@MainActor
private struct MountedLookupContinuationStateOwner {
    @State var value = 23
}

@MainActor
private struct MountedLookupContinuationSeedOwner {
    @StateObject var model: MountedLookupContinuationSeedObject

    init(events: MountedLookupContinuationEvents) {
        _model = StateObject(wrappedValue: MountedLookupContinuationSeedObject(events: events))
    }
}

@MainActor
private final class MountedLookupContinuationSeedObject: ObservableObject {
    let events: MountedLookupContinuationEvents

    init(events: MountedLookupContinuationEvents) {
        self.events = events
        events.objectSeeds += 1
    }
}

@MainActor
private struct MountedLookupContinuationInstalledState {
    let owner: StateMountOwner
    let epoch: StateMountEpoch
    let value: Binding<Int>
}

@MainActor
private final class MountedLookupContinuationLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { nil }
}

private enum MountedLookupContinuationMode {
    case descriptor
    case lazy
}

private enum MountedLookupContinuationSite: Equatable {
    case hash
    case collisionEquality
    case scopeEquality
}
