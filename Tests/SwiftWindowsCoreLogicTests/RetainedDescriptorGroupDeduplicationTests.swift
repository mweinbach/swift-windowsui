import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Construction and adoption semantics only; these tests make no timing claim.
@MainActor
final class RetainedDescriptorGroupDeduplicationTests: XCTestCase {
    func testWideGroupDeduplicatesSourcesWithoutChangingRequiredFacetOrder() async throws {
        let fixture = DescriptorDeduplicationFixture()
        defer { fixture.finish() }
        let component = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(component.registerGroup(kind: .structure))
        let sources = (0..<64).map { _ in ViewNode() }
        for source in sources { XCTAssertTrue(component.recordSourceOutput(source, group: group)) }
        for _ in 0..<3 {
            for source in sources.reversed() {
                XCTAssertTrue(component.recordSourceOutput(source, group: group))
            }
        }
        let proposal = try XCTUnwrap(component.closeGroup(group))
        XCTAssertEqual(proposal.requiredFacets.count, sources.count * 2)
        XCTAssertEqual(Set(proposal.requiredFacets.map(ObjectIdentifier.init)).count, sources.count * 2)

        let adopted = try fixture.adopt(sources, group: group)

        XCTAssertTrue(adopted.group.receipt.isActive)
        XCTAssertEqual(adopted.group.acceptedFacets.count, sources.count * 2)
        assertDescriptorDeduplicationFacetOrder(
            proposal, in: adopted.group, targets: adopted.targets,
            expected: sources.indices.flatMap { ["\($0):attachment", "\($0):completion"] })
    }

    func testScopedTaskDeduplicationPreservesPayloadAndDeclarationFacetOrder() async throws {
        let fixture = DescriptorDeduplicationFixture()
        defer { fixture.finish() }
        let component = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(component.registerGroup(kind: .scopedTask))
        let sources = (0..<12).map { _ in ViewNode() }
        let declarations = (0..<3).map { _ in RetainedTaskDeclarationID() }
        var payloads: [RetainedLazyListSourcePayloadID] = []
        var expected: [String] = []
        for index in 0..<6 {
            payloads.append(try XCTUnwrap(component.recordTaskSourceOutput(sources[index], group: group)))
            expected += ["\(index):attachment", "\(index):appear", "\(index):disappear"]
        }
        XCTAssertTrue(component.registerTaskDeclaration(declarations[0], group: group))
        expected += (0..<6).map { "\($0):task0" }
        for index in 6..<sources.count {
            payloads.append(try XCTUnwrap(component.recordTaskSourceOutput(sources[index], group: group)))
            expected += ["\(index):attachment", "\(index):appear", "\(index):disappear", "\(index):task0"]
        }
        for declaration in declarations.dropFirst() {
            XCTAssertTrue(component.registerTaskDeclaration(declaration, group: group))
            let index = try XCTUnwrap(declarations.firstIndex { $0 === declaration })
            expected += sources.indices.map { "\($0):task\(index)" }
        }
        for _ in 0..<3 {
            for declaration in declarations.reversed() {
                XCTAssertTrue(component.registerTaskDeclaration(declaration, group: group))
            }
            for index in sources.indices.reversed() {
                XCTAssertTrue(component.recordTaskSourceOutput(sources[index], group: group) === payloads[index])
            }
        }
        XCTAssertEqual(Set(payloads.map(ObjectIdentifier.init)).count, sources.count)
        let proposal = try XCTUnwrap(component.closeGroup(group))
        XCTAssertEqual(proposal.requiredFacets.count, sources.count * (3 + declarations.count))

        let adopted = try fixture.adopt(sources, group: group, declarations: declarations)
        let taskGroup = try XCTUnwrap(fixture.journal.takeAcceptedDescriptorTaskGroups().first)

        XCTAssertEqual(
            taskGroup.members.map { ObjectIdentifier($0.sourcePayload) }, payloads.map(ObjectIdentifier.init))
        XCTAssertEqual(taskGroup.declarationIDs.map(ObjectIdentifier.init), declarations.map(ObjectIdentifier.init))
        XCTAssertTrue(taskGroup.members.allSatisfy { $0.requiredFacets.count == 3 + declarations.count })
        assertDescriptorDeduplicationFacetOrder(
            proposal, in: adopted.group, targets: adopted.targets, declarations: declarations, expected: expected)
    }

    func testRejectingFirstMiddleOrLastOutputKeepsSurvivorsOrderedAndDeduplicated() async throws {
        for rejectedIndex in 0..<3 {
            let fixture = DescriptorDeduplicationFixture()
            defer { fixture.finish() }
            let component = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
            let group = try XCTUnwrap(component.registerGroup(kind: .structure))
            let child = try XCTUnwrap(component.registerChildComponent())
            let childGroup = try XCTUnwrap(child.registerGroup(kind: .structure))
            let original = (0..<3).map { _ in ViewNode() }
            for index in original.indices {
                if index == rejectedIndex {
                    XCTAssertTrue(child.recordSourceOutput(original[index], group: childGroup))
                } else {
                    XCTAssertTrue(component.recordSourceOutput(original[index], group: group))
                }
            }

            child.rejectComponent()

            XCTAssertFalse(child.canConstruct)
            XCTAssertFalse(component.recordSourceOutput(original[rejectedIndex], group: group))
            XCTAssertTrue(try XCTUnwrap(child.closeGroup(childGroup)).requiredFacets.isEmpty)
            var survivors = original.enumerated().filter { $0.offset != rejectedIndex }.map(\.element)
            for source in survivors.reversed() {
                XCTAssertTrue(component.recordSourceOutput(source, group: group))
            }
            let later = ViewNode()
            survivors.append(later)
            XCTAssertTrue(component.recordSourceOutput(later, group: group))
            XCTAssertTrue(component.recordSourceOutput(later, group: group))
            let proposal = try XCTUnwrap(component.closeGroup(group))
            XCTAssertEqual(proposal.requiredFacets.count, survivors.count * 2)

            let adopted = try fixture.adopt(survivors, group: group)

            assertDescriptorDeduplicationFacetOrder(
                proposal, in: adopted.group, targets: adopted.targets,
                expected: survivors.indices.flatMap { ["\($0):attachment", "\($0):completion"] })
        }
    }

    func testRemovingEveryOutputAllowsNewSourcesInTheOpenAncestorGroup() async throws {
        let fixture = DescriptorDeduplicationFixture()
        defer { fixture.finish() }
        let component = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(component.registerGroup(kind: .structure))
        let child = try XCTUnwrap(component.registerChildComponent())
        let childGroup = try XCTUnwrap(child.registerGroup(kind: .structure))
        let removed = ViewNode()
        XCTAssertTrue(child.recordSourceOutput(removed, group: childGroup))
        child.rejectComponent()
        XCTAssertFalse(component.recordSourceOutput(removed, group: group))
        let replacement = ViewNode()
        XCTAssertTrue(component.recordSourceOutput(replacement, group: group))
        XCTAssertTrue(component.recordSourceOutput(replacement, group: group))
        let proposal = try XCTUnwrap(component.closeGroup(group))
        XCTAssertEqual(proposal.requiredFacets.count, 2)

        let adopted = try fixture.adopt([replacement], group: group)

        assertDescriptorDeduplicationFacetOrder(
            proposal, in: adopted.group, targets: adopted.targets, expected: ["0:attachment", "0:completion"])
    }

    func testExpiredSourcesReleaseCapturesBeforeReplacementRegistration() async throws {
        let fixture = DescriptorDeduplicationFixture()
        defer { fixture.finish() }
        let component = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(component.registerGroup(kind: .scopedTask))
        XCTAssertTrue(component.registerTaskDeclaration(RetainedTaskDeclarationID(), group: group))
        let releases = DescriptorDeduplicationReleases()
        var source: ViewNode? = descriptorDeduplicationSourceWithCapture(releases)
        weak var weakSource = source
        let originalPayload = try XCTUnwrap(component.recordTaskSourceOutput(try XCTUnwrap(source), group: group))

        source = nil

        XCTAssertNil(weakSource)
        XCTAssertEqual(releases.count, 1, "Native lookup metadata must not extend authored capture lifetime")
        let replacement = ViewNode()
        replacement.retainedViewIdentity = RetainedViewIdentity()
        let replacementPayload = try XCTUnwrap(component.recordTaskSourceOutput(replacement, group: group))
        XCTAssertFalse(replacementPayload === originalPayload)
        XCTAssertTrue(component.recordTaskSourceOutput(replacement, group: group) === replacementPayload)
        // The original weak output is not silently removed when its node expires.
        XCTAssertEqual(try XCTUnwrap(component.closeGroup(group)).requiredFacets.count, 8)
        XCTAssertEqual(releases.count, 1)
    }

    func testNativeDeduplicationDoesNotReadAuthoredIdentityEqualityOrHash() async throws {
        let fixture = DescriptorDeduplicationFixture()
        defer { fixture.finish() }
        let component = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(component.registerGroup(kind: .structure))
        let calls = DescriptorDeduplicationIdentityCalls()
        let sources = (0..<16).map { _ -> ViewNode in
            let node = ViewNode()
            node.retainedViewIdentity = RetainedViewIdentity(segments: [
                .explicit(.init(DescriptorDeduplicationKey(calls)))
            ])
            return node
        }
        calls.equalities = 0
        calls.hashes = 0

        for source in sources { XCTAssertTrue(component.recordSourceOutput(source, group: group)) }
        for source in sources.reversed() { XCTAssertTrue(component.recordSourceOutput(source, group: group)) }

        XCTAssertEqual(calls.equalities, 0)
        XCTAssertEqual(calls.hashes, 0)
        XCTAssertEqual(try XCTUnwrap(component.closeGroup(group)).requiredFacets.count, sources.count * 2)
        withExtendedLifetime(sources) {}
    }

    func testWarmLookupCannotBypassConstructionOrRejectedSubtreeGuards() async throws {
        for invalidation in DescriptorDeduplicationInvalidation.allCases {
            let fixture = DescriptorDeduplicationFixture()
            defer { fixture.finish() }
            let component = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
            let group = try XCTUnwrap(component.registerGroup(kind: .structure))
            let source = ViewNode()
            XCTAssertTrue(component.recordSourceOutput(source, group: group))
            XCTAssertTrue(component.recordSourceOutput(source, group: group))
            switch invalidation {
            case .closedGroup: _ = component.closeGroup(group)
            case .hostClosed: fixture.runtime.lazyListLogicalHostLifetime.revoke()
            case .ownerClosed: fixture.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime.revoke()
            case .superseded: fixture.scope.noteSupersedingRequest()
            case .prepared: fixture.scope.preparationDidSucceed()
            case .rejectedSubtree:
                let child = ViewNode()
                source.addChild(child)
                child.markRejectedRetainedSource()
            }

            XCTAssertFalse(component.recordSourceOutput(source, group: group))
            XCTAssertEqual(try XCTUnwrap(component.closeGroup(group)).requiredFacets.count, 2)
        }
    }
}

private enum DescriptorDeduplicationInvalidation: CaseIterable {
    case closedGroup, hostClosed, ownerClosed, superseded, prepared, rejectedSubtree
}

@MainActor
private final class DescriptorDeduplicationFixture {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal

    init() {
        let runtime = RetainedViewRuntime(root: ViewNode())
        self.runtime = runtime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
    }

    func adopt(
        _ sources: [ViewNode], group: RetainedDescriptorGroupID, declarations: [RetainedTaskDeclarationID] = []
    ) throws -> (group: RetainedDescriptorAcceptedGroup, targets: [ViewNode]) {
        let targets = sources.map { _ in ViewNode() }
        let callbackFields: [PartialKeyPath<ViewNode>] = [\ViewNode.onAppearWithNode, \ViewNode.onDisappearWithNode]
        for target in targets { runtime.root.addChild(target) }
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
        // Acceptance order is deliberately different from construction order.
        for index in sources.indices.reversed() {
            let source = sources[index]
            let target = targets[index]
            _ = journal.recordAcceptedAttachment(from: source, to: target)
            if declarations.isEmpty {
                _ = journal.recordCompletedNode(from: source, to: target)
            } else {
                for keyPath in callbackFields {
                    XCTAssertTrue(journal.preparePropertyCopy(from: source, to: target, keyPath: keyPath))
                    _ = journal.recordAcceptedProperty(from: source, to: target, keyPath: keyPath)
                }
                journal.recordAcceptedDescriptorTaskDeclarationTransport(
                    from: source, to: target, declarationIDs: declarations)
            }
        }
        let disposition = journal.seal(completedCheckedAdoption: true)
        let accepted = try XCTUnwrap(disposition.acceptedOrdinaryGroups.first { $0.proposal.group === group })
        return (accepted, targets)
    }

    func finish() {
        journal.releaseUnadoptedTransport()
        scope.finish()
    }
}

@MainActor
private func assertDescriptorDeduplicationFacetOrder(
    _ proposal: RetainedDescriptorGroupProposal, in accepted: RetainedDescriptorAcceptedGroup,
    targets: [ViewNode], declarations: [RetainedTaskDeclarationID] = [], expected: [String],
    file: StaticString = #filePath, line: UInt = #line
) {
    let fields = proposal.requiredFacets.map { id -> String in
        guard let facet = accepted.acceptedFacets.first(where: { $0.facet === id }),
            let index = targets.firstIndex(where: { $0 === facet.actual.node })
        else { return "missing" }
        let label: String
        switch facet.nativeField {
        case .childAttachment: label = "attachment"
        case .nodeCompletion: label = "completion"
        case .nodeProperty(let keyPath):
            if keyPath == \ViewNode.onAppearWithNode {
                label = "appear"
            } else if keyPath == \ViewNode.onDisappearWithNode {
                label = "disappear"
            } else {
                label = "unexpectedProperty"
            }
        case .scopedTaskDeclaration(let declaration):
            label = declarations.firstIndex(where: { $0 === declaration }).map { "task\($0)" } ?? "missingTask"
        case .listDescriptor: label = "unexpectedDescriptor"
        }
        return "\(index):\(label)"
    }
    XCTAssertEqual(fields, expected, file: file, line: line)
}

@MainActor
private final class DescriptorDeduplicationReleases {
    var count = 0
}

@MainActor
private final class DescriptorDeduplicationCapture {
    let releases: DescriptorDeduplicationReleases
    init(_ releases: DescriptorDeduplicationReleases) { self.releases = releases }
    isolated deinit { releases.count += 1 }
}

@MainActor
@inline(never)
private func descriptorDeduplicationSourceWithCapture(_ releases: DescriptorDeduplicationReleases) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity()
    let capture = DescriptorDeduplicationCapture(releases)
    node.onAppear = { withExtendedLifetime(capture) {} }
    return node
}

@MainActor
private final class DescriptorDeduplicationIdentityCalls {
    var equalities = 0
    var hashes = 0
}

private struct DescriptorDeduplicationKey: Hashable {
    let calls: DescriptorDeduplicationIdentityCalls
    init(_ calls: DescriptorDeduplicationIdentityCalls) { self.calls = calls }
    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.calls.equalities += 1 }
        return true
    }
    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { calls.hashes += 1 }
        hasher.combine(0)
    }
}

@MainActor
final class RetainedDescriptorOutputMembershipTests: XCTestCase {
    func testPropertyCopyMembershipTracksSurvivorsAfterFirstMiddleAndLastRemoval() async throws {
        for rejectedIndex in [0, 2, 4] {
            let fixture = DescriptorDeduplicationFixture()
            defer { fixture.finish() }
            let component = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
            let group = try XCTUnwrap(component.registerGroup(kind: .scopedTask))
            let declaration = RetainedTaskDeclarationID()
            XCTAssertTrue(component.registerTaskDeclaration(declaration, group: group))
            let child = try XCTUnwrap(component.registerChildComponent())
            let childGroup = try XCTUnwrap(child.registerGroup(kind: .structure))
            let calls = DescriptorDeduplicationIdentityCalls()
            let original = (0..<5).map { _ -> ViewNode in
                let source = ViewNode()
                source.retainedViewIdentity = RetainedViewIdentity(segments: [
                    .explicit(.init(DescriptorDeduplicationKey(calls)))
                ])
                return source
            }
            var payloads: [ObjectIdentifier: RetainedLazyListSourcePayloadID] = [:]
            for index in original.indices {
                let source = original[index]
                if index == rejectedIndex {
                    XCTAssertTrue(child.recordSourceOutput(source, group: childGroup))
                } else {
                    payloads[ObjectIdentifier(source)] = try XCTUnwrap(
                        component.recordTaskSourceOutput(source, group: group))
                }
            }
            child.rejectComponent()
            XCTAssertTrue(try XCTUnwrap(child.closeGroup(childGroup)).requiredFacets.isEmpty)
            XCTAssertNil(component.recordTaskSourceOutput(original[rejectedIndex], group: group))
            var survivors = original.enumerated().filter { $0.offset != rejectedIndex }.map(\.element)
            let later = ViewNode()
            later.retainedViewIdentity = RetainedViewIdentity(segments: [
                .explicit(.init(DescriptorDeduplicationKey(calls)))
            ])
            payloads[ObjectIdentifier(later)] = try XCTUnwrap(component.recordTaskSourceOutput(later, group: group))
            survivors.append(later)
            let proposal = try XCTUnwrap(component.closeGroup(group))
            XCTAssertEqual(proposal.requiredFacets.count, survivors.count * 4)
            calls.equalities = 0
            calls.hashes = 0

            // This helper prepares and accepts both callback properties for
            // every survivor, in reverse order. It exercises ownedOutputs
            // after shifted indices and the subsequent append, not merely
            // source registration's deduplication lookup.
            let adopted = try fixture.adopt(survivors, group: group, declarations: [declaration])
            let taskGroup = try XCTUnwrap(fixture.journal.takeAcceptedDescriptorTaskGroups().first)

            XCTAssertEqual(calls.equalities, 0)
            XCTAssertEqual(calls.hashes, 0)
            XCTAssertTrue(adopted.group.receipt.isActive)
            XCTAssertEqual(
                taskGroup.members.map { ObjectIdentifier($0.sourcePayload) },
                try survivors.map { ObjectIdentifier(try XCTUnwrap(payloads[ObjectIdentifier($0)])) })
            assertDescriptorDeduplicationFacetOrder(
                proposal, in: adopted.group, targets: adopted.targets, declarations: [declaration],
                expected: survivors.indices.flatMap {
                    ["\($0):attachment", "\($0):appear", "\($0):disappear", "\($0):task0"]
                })
        }
    }
}
