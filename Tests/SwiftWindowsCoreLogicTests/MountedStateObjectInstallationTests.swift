import SwiftWindowsCore
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class MountedStateObjectInstallationTests: XCTestCase {
    func testObjectFactoryRunsOnceForRepeatedClaimsAndIsNotRunDuringReuse() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(initial.owner(at: identity("reused")))
        var factoryCalls = 0
        let first = try owner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
            factoryCalls += 1
            return ObjectInstallationModel(factoryCalls)
        }
        let second = try owner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
            factoryCalls += 1
            return ObjectInstallationModel(factoryCalls)
        }
        XCTAssertTrue(first === second)
        XCTAssertEqual(factoryCalls, 1)
        commit(initial)
        let replacementInput = try XCTUnwrap(registry.beginRootBuild())
        let sameOwner = try XCTUnwrap(replacementInput.owner(at: owner.identity))
        let reused = try sameOwner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
            factoryCalls += 1
            registry.close()
            return ObjectInstallationModel(99)
        }
        XCTAssertTrue(reused === first)
        XCTAssertTrue(reused.readValue() === first.readValue())
        XCTAssertEqual(factoryCalls, 1, "An unused replacement factory must have no side effects")
        XCTAssertFalse(registry.isClosed)
        replacementInput.abort()
        XCTAssertTrue(first.isWritable)
    }

    func testAFactoryCanResolveOtherSlotsAndOwnersWithoutAFalseCycle() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        let firstOwner = try XCTUnwrap(epoch.owner(at: identity("first")))
        let secondOwner = try XCTUnwrap(epoch.owner(at: identity("second")))
        var otherSlot: MountedStateCell<ObjectInstallationModel>?
        var otherOwner: MountedStateCell<ObjectInstallationModel>?
        let first = try firstOwner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
            do {
                otherSlot = try firstOwner.resolveObject(at: ObjectInstallationSlots.secondSlot) {
                    ObjectInstallationModel(2)
                }
                otherOwner = try secondOwner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
                    ObjectInstallationModel(3)
                }
            } catch {
                XCTFail("Independent object declarations cannot form a creation cycle: \(error)")
            }
            return ObjectInstallationModel(1)
        }
        XCTAssertEqual(first.readValue().serial, 1)
        XCTAssertEqual(otherSlot?.readValue().serial, 2)
        XCTAssertEqual(otherOwner?.readValue().serial, 3)
        commit(epoch)
        XCTAssertEqual(registry.liveOwnerCount, 2)
        XCTAssertTrue(first.isWritable)
        XCTAssertTrue(otherSlot?.isWritable == true)
        XCTAssertTrue(otherOwner?.isWritable == true)
    }

    func testRecursiveObjectCreationRejectsTheCandidateWithoutCallingTheNestedFactory() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(initial.owner(at: identity("cycle")))
        var outerCalls = 0
        var nestedCalls = 0
        var recursiveReason: DynamicPropertyInstallationError.Reason?
        weak var unusedObject: ObjectInstallationModel?
        do {
            _ = try owner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
                outerCalls += 1
                do {
                    _ = try owner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
                        nestedCalls += 1
                        return ObjectInstallationModel(2)
                    }
                } catch {
                    recursiveReason = (error as? DynamicPropertyInstallationError)?.reason
                }
                let object = ObjectInstallationModel(1)
                unusedObject = object
                return object
            }
            XCTFail("A recursively initialized declaration cannot be adopted")
        } catch {
            assertReason(error, .ownerUnavailable)
        }
        XCTAssertEqual(recursiveReason, .recursiveInitialization)
        XCTAssertEqual(outerCalls, 1)
        XCTAssertEqual(nestedCalls, 0)
        XCTAssertFalse(initial.canAdopt)
        XCTAssertNil(unusedObject)
        initial.abort()
        XCTAssertEqual(registry.liveOwnerCount, 0)
        let replacement = try XCTUnwrap(registry.beginRootBuild())
        let replacementOwner = try XCTUnwrap(replacement.owner(at: owner.identity))
        XCTAssertNotEqual(replacementOwner.generation, owner.generation)
        let cell = try replacementOwner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
            ObjectInstallationModel(3)
        }
        commit(replacement)
        XCTAssertTrue(cell.isWritable, "The previous reservation must not poison a new mount generation")
        XCTAssertEqual(cell.readValue().serial, 3)
    }

    func testAbortedSupersededAndClosingFactoriesCannotPublishTheirObjects() async throws {
        for interruption in ObjectInstallationInterruption.allCases {
            let registry = StateMountRegistry()
            defer { registry.close() }
            let epoch = try XCTUnwrap(registry.beginRootBuild())
            let owner = try XCTUnwrap(epoch.owner(at: identity("interrupted")))
            weak var object: ObjectInstallationModel?
            do {
                _ = try owner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
                    switch interruption {
                    case .abort: epoch.abort()
                    case .supersede: epoch.supersede()
                    case .close: registry.close()
                    }
                    let result = ObjectInstallationModel(1)
                    object = result
                    return result
                }
                XCTFail("The \(interruption) factory must not return an owned cell")
            } catch {
                assertReason(error, .ownerUnavailable)
            }
            epoch.abort()
            XCTAssertFalse(epoch.didCommit)
            XCTAssertEqual(registry.liveOwnerCount, 0)
            XCTAssertNil(object)
            XCTAssertFalse(owner.isInstallationActive)
        }
    }

    func testAnOldFactoryCannotClaimOrCancelAReplacementEpochStartedDuringItsCallback() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let original = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(original.owner(at: identity("replacement")))
        var replacement: StateMountEpoch?
        var replacementOwner: StateMountOwner?
        var replacementCell: MountedStateCell<ObjectInstallationModel>?
        weak var abandonedObject: ObjectInstallationModel?
        do {
            _ = try owner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
                original.abort()
                if let next = registry.beginRootBuild(), let nextOwner = next.owner(at: owner.identity) {
                    replacement = next
                    replacementOwner = nextOwner
                    do {
                        replacementCell = try nextOwner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
                            ObjectInstallationModel(2)
                        }
                    } catch {
                        XCTFail("The replacement epoch must have independent creation ownership: \(error)")
                    }
                } else {
                    XCTFail("The completed old epoch must leave room for its replacement")
                }
                let object = ObjectInstallationModel(1)
                abandonedObject = object
                return object
            }
            XCTFail("The old factory must not publish into its replacement epoch")
        } catch {
            assertReason(error, .ownerUnavailable)
        }
        original.abort()
        let next = try XCTUnwrap(replacement)
        let nextOwner = try XCTUnwrap(replacementOwner)
        let cell = try XCTUnwrap(replacementCell)
        XCTAssertNotEqual(nextOwner.generation, owner.generation)
        XCTAssertTrue(next.canAdopt)
        XCTAssertNil(abandonedObject)
        commit(next)
        XCTAssertTrue(registry.owner(at: owner.identity) === nextOwner)
        XCTAssertEqual(cell.readValue().serial, 2)
        XCTAssertTrue(cell.isWritable)
    }

    func testAdoptionCannotStartUntilEveryObjectFactoryHasReturned() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let oldOwner = try XCTUnwrap(initial.owner(at: identity("outgoing")))
        let outgoing = oldOwner.resolve(at: ObjectInstallationSlots.firstSlot) { 0 }
        commit(initial)
        let candidate = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(candidate.owner(at: identity("incoming")))
        _ = try owner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
            XCTAssertFalse(candidate.prepareForAdoption())
            XCTAssertTrue(outgoing.isWritable, "Incomplete factory construction must not revoke the committed tree")
            return ObjectInstallationModel(1)
        }
        XCTAssertTrue(candidate.prepareForAdoption())
        XCTAssertFalse(outgoing.isWritable)
        candidate.commitAdoption()
        registry.finishPendingRetirements()
        XCTAssertTrue(candidate.didCommit)
    }

    func testMetadataPreflightRejectsImmutableObjectOwnershipBeforeItsFactoryRuns() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(epoch.owner(at: identity("immutable")))
        var calls = 0
        let source = ObjectInstallationImmutableFixture {
            calls += 1
            return ObjectInstallationModel(calls)
        }
        XCTAssertEqual(calls, 0)
        do {
            _ = try DynamicPropertyInstaller.install(source, in: owner)
            XCTFail("An immutable stored StateObject cannot receive an independent mounted cell")
        } catch {
            assertReason(error, .immutableProperty)
        }
        XCTAssertEqual(calls, 0, "Preflight must finish before object creation has any side effects")
        epoch.abort()
        XCTAssertEqual(registry.liveOwnerCount, 0)
    }

    func testDiscardedObjectCandidatesReleaseTheirCellsAndKeepDeclaredCommittedObjects() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let stableIdentity = identity("declared")
        let rejectedIdentity = identity("rejected")
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let stableOwner = try XCTUnwrap(initial.owner(at: stableIdentity))
        weak var stableObject: ObjectInstallationModel?
        _ = try stableOwner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
            let object = ObjectInstallationModel(1)
            stableObject = object
            return object
        }
        commit(initial)
        let candidate = try XCTUnwrap(registry.beginRootBuild())
        candidate.preserveDeclaredSubtree(at: stableIdentity)
        let rejectedOwner = try XCTUnwrap(candidate.owner(at: rejectedIdentity))
        weak var rejectedObject: ObjectInstallationModel?
        _ = try rejectedOwner.resolveObject(at: ObjectInstallationSlots.firstSlot) {
            let object = ObjectInstallationModel(2)
            rejectedObject = object
            return object
        }
        XCTAssertNotNil(rejectedObject)
        candidate.discardUnadoptedSubtree(at: rejectedIdentity, preserveCommitted: false)
        XCTAssertNil(rejectedObject)
        commit(candidate)
        XCTAssertEqual(stableObject?.serial, 1)
        XCTAssertTrue(registry.owner(at: stableIdentity) === stableOwner)
        XCTAssertNil(registry.owner(at: rejectedIdentity))
        registry.close()
        XCTAssertNil(stableObject)
    }

    private func identity(_ name: String) -> RetainedViewIdentity {
        RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObjectInstallationSlots.self)), .keyed(.init(name))])
    }

    private func commit(_ epoch: StateMountEpoch, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(epoch.prepareForAdoption(), file: file, line: line)
        epoch.commitAdoption()
        XCTAssertTrue(epoch.didCommit, file: file, line: line)
    }

    private func assertReason(
        _ error: Error, _ reason: DynamicPropertyInstallationError.Reason,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual((error as? DynamicPropertyInstallationError)?.reason, reason, file: file, line: line)
    }
}

private enum ObjectInstallationInterruption: CaseIterable {
    case abort
    case supersede
    case close
}

@MainActor
private final class ObjectInstallationModel: ObservableObject {
    let serial: Int

    init(_ serial: Int) { self.serial = serial }
}

@MainActor
private struct ObjectInstallationImmutableFixture {
    let object: StateObject<ObjectInstallationModel>

    init(factory: @escaping @MainActor () -> ObjectInstallationModel) {
        object = StateObject(wrappedValue: factory())
    }
}

private struct ObjectInstallationSlots {
    var first: StateObject<ObjectInstallationModel>
    var second: StateObject<ObjectInstallationModel>

    static var firstSlot: StatePropertySlot {
        StatePropertySlot(
            declaration: [\Self.first],
            concreteTypes: [ObjectIdentifier(Self.self), ObjectIdentifier(StateObject<ObjectInstallationModel>.self)])
    }

    static var secondSlot: StatePropertySlot {
        StatePropertySlot(
            declaration: [\Self.second],
            concreteTypes: [ObjectIdentifier(Self.self), ObjectIdentifier(StateObject<ObjectInstallationModel>.self)])
    }
}
