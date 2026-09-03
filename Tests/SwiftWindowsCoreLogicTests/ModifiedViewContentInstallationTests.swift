import SwiftWindowsCore
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class ModifiedViewContentInstallationTests: XCTestCase {
    func testCustomDynamicContentKeepsImmutableDiagnosticBeforeAuthoredEffects() async throws {
        let harness = try ModifiedStorageInstallationHarness()
        defer { harness.close() }
        let events = ModifiedStorageInstallationEvents()
        let source = subject(ModifiedStorageCustomContent(events: events), events: events)

        assertFailure(source, in: harness, reason: .immutableProperty, events: events)
    }

    func testOwningDynamicContentRejectsBeforeSeedInstallOrUpdate() async throws {
        let harness = try ModifiedStorageInstallationHarness()
        defer { harness.close() }
        let events = ModifiedStorageInstallationEvents()
        let source = subject(ModifiedStorageOwningContent(events: events), events: events)

        assertFailure(source, in: harness, reason: .immutableProperty, events: events)
        XCTAssertTrue(events.slots.isEmpty)
        XCTAssertEqual(source.content.value, 17)
    }

    func testTrustedNonOwningStructContentInstallsWithoutChangingStoredCopies() async throws {
        let first = try ModifiedStorageInstallationHarness()
        let second = try ModifiedStorageInstallationHarness()
        defer {
            first.close()
            second.close()
        }
        let events = ModifiedStorageInstallationEvents()
        let source = subject(ModifiedStorageTrustedContent(events: events, value: 41), events: events)
        let sibling = source
        XCTAssertTrue(events.entries.isEmpty, "Constructing modifier storage must not inspect authored metadata")

        let firstCopy = try first.install(source)
        let secondCopy = try second.install(sibling)
        var localContent = firstCopy.content
        localContent.value = 99

        XCTAssertEqual(localContent.value, 99)
        XCTAssertEqual(source.content.value, 41)
        XCTAssertEqual(sibling.content.value, 41)
        XCTAssertEqual(firstCopy.content.value, 41)
        XCTAssertEqual(secondCopy.content.value, 41)
        XCTAssertTrue(events.entries.isEmpty, "Trusted implementation details must not install or evaluate views")
        XCTAssertTrue(events.slots.isEmpty)
    }

    func testTrustedNonOwningClassContentKeepsUnsupportedKindDiagnostic() async throws {
        let harness = try ModifiedStorageInstallationHarness()
        defer { harness.close() }
        let events = ModifiedStorageInstallationEvents()
        let source = subject(ModifiedStorageTrustedClassContent(events: events), events: events)

        assertFailure(source, in: harness, reason: .unsupportedValueKind, events: events)
    }

    func testTrustedNonOwningEnumContentKeepsUnsupportedKindDiagnostic() async throws {
        let harness = try ModifiedStorageInstallationHarness()
        defer { harness.close() }
        let events = ModifiedStorageInstallationEvents()
        let source = subject(ModifiedStorageTrustedEnumContent.value(events), events: events)

        assertFailure(source, in: harness, reason: .unsupportedValueKind, events: events)
    }

    func testCustomClassContentRefusesImmutableAccessBeforeInspectingItsKind() async throws {
        let harness = try ModifiedStorageInstallationHarness()
        defer { harness.close() }
        let events = ModifiedStorageInstallationEvents()
        let source = subject(ModifiedStorageCustomClassContent(events: events), events: events)

        assertFailure(source, in: harness, reason: .immutableProperty, events: events)
    }

    func testCustomEnumContentRefusesImmutableAccessBeforeInspectingItsKind() async throws {
        let harness = try ModifiedStorageInstallationHarness()
        defer { harness.close() }
        let events = ModifiedStorageInstallationEvents()
        let source = subject(ModifiedStorageCustomEnumContent.value(events), events: events)

        assertFailure(source, in: harness, reason: .immutableProperty, events: events)
    }

    func testImmutableContentRefusalPrecedesItsNestedFieldMetadataInspection() async throws {
        let harness = try ModifiedStorageInstallationHarness()
        defer { harness.close() }
        let events = ModifiedStorageInstallationEvents()
        let source = subject(ModifiedStorageAmbiguousContent(events: events), events: events)

        // The nested stored Void would fail field coverage if this content were
        // prepared first. The original immutable declaration refuses it earlier.
        assertFailure(source, in: harness, reason: .immutableProperty, events: events)
    }

    private func subject<Content: View>(
        _ content: Content, events: ModifiedStorageInstallationEvents
    ) -> ModifiedView<Content> {
        ModifiedView(content: content) { value, context in
            events.entries.append("transform")
            return value.makeComponent(context: context)
        }
    }

    private func assertFailure<Content: View>(
        _ source: ModifiedView<Content>, in harness: ModifiedStorageInstallationHarness,
        reason: DynamicPropertyInstallationError.Reason, events: ModifiedStorageInstallationEvents,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            events.entries.isEmpty, "Constructing modifier storage must not inspect authored metadata",
            file: file, line: line)
        do {
            _ = try harness.install(source)
            XCTFail("Expected installation to fail with \(reason)", file: file, line: line)
        } catch let error as DynamicPropertyInstallationError {
            let contentType = String(reflecting: Content.self)
            let declaration = "\(String(reflecting: ModifiedView<Content>.self)) -> \(contentType)"
            XCTAssertEqual(error.reason, reason, error.description, file: file, line: line)
            XCTAssertEqual(error.type, contentType, file: file, line: line)
            XCTAssertEqual(error.declaration, [declaration], file: file, line: line)
            if reason == .immutableProperty {
                XCTAssertEqual(
                    error.detail, "Owning and custom DynamicProperty declarations require typed writable access",
                    file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected installation error: \(error)", file: file, line: line)
        }
        XCTAssertTrue(
            events.entries.isEmpty, "Refusal must precede seed, install, update, transform, body, and metadata effects",
            file: file, line: line)
        XCTAssertTrue(events.slots.isEmpty, file: file, line: line)
    }
}

@MainActor
private final class ModifiedStorageInstallationHarness {
    let registry: StateMountRegistry
    let epoch: StateMountEpoch
    let owner: StateMountOwner

    init() throws {
        registry = StateMountRegistry(invalidate: {})
        epoch = try XCTUnwrap(registry.beginRootBuild())
        owner = try XCTUnwrap(epoch.owner(at: .init()))
    }

    func install<Root>(_ source: Root) throws -> Root {
        try DynamicPropertyInstaller.install(source, in: owner)
    }

    func close() {
        registry.close()
        epoch.abort()
    }
}

@MainActor
private final class ModifiedStorageInstallationEvents {
    var entries: [String] = []
    var slots: [StatePropertySlot] = []
}

@MainActor
private protocol ModifiedStorageObservedView: View, TaggedViewMetadata where Body == EmptyView {
    var events: ModifiedStorageInstallationEvents { get }
}

extension ModifiedStorageObservedView {
    var body: EmptyView {
        events.entries.append("body")
        return EmptyView()
    }

    var anySelectionTag: AnyHashable? {
        events.entries.append("metadata")
        return nil
    }
}

@MainActor
private struct ModifiedStorageCustomContent: ModifiedStorageObservedView, DynamicProperty {
    let events: ModifiedStorageInstallationEvents

    nonisolated mutating func update() {
        MainActor.assumeIsolated { events.entries.append("update:custom") }
    }
}

@MainActor
private struct ModifiedStorageOwningContent: ModifiedStorageObservedView, MountedDynamicProperty {
    let events: ModifiedStorageInstallationEvents
    private var cell: MountedStateCell<Int>?

    init(events: ModifiedStorageInstallationEvents) { self.events = events }

    var value: Int { cell?.readValue() ?? 17 }

    mutating func install(in owner: StateMountOwner, at slot: StatePropertySlot) {
        events.entries.append("install:owning")
        events.slots.append(slot)
        cell = owner.resolve(at: slot) {
            events.entries.append("seed:owning")
            return 17
        }
    }

    func isInstalled(in owner: StateMountOwner, at slot: StatePropertySlot) -> Bool {
        events.entries.append("validate:owning")
        guard let cell else { return false }
        return owner.isInstalled(cell: cell, at: slot)
    }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { events.entries.append("update:owning") }
    }
}

@MainActor
private struct ModifiedStorageTrustedContent: ModifiedStorageObservedView, NonOwningDynamicProperty {
    let events: ModifiedStorageInstallationEvents
    var value: Int
    // A trusted leaf's private implementation must not become a declaration.
    private let implementation: ModifiedStorageOwningContent

    init(events: ModifiedStorageInstallationEvents, value: Int) {
        self.events = events
        self.value = value
        implementation = ModifiedStorageOwningContent(events: events)
    }
    // Deliberately uses DynamicProperty's no-op update, as immutable trusted
    // leaves promise. Mutating a separately returned content copy remains local.
}

@MainActor
private final class ModifiedStorageTrustedClassContent: ModifiedStorageObservedView, NonOwningDynamicProperty {
    let events: ModifiedStorageInstallationEvents
    init(events: ModifiedStorageInstallationEvents) { self.events = events }
}

@MainActor
private enum ModifiedStorageTrustedEnumContent: ModifiedStorageObservedView, NonOwningDynamicProperty {
    case value(ModifiedStorageInstallationEvents)

    var events: ModifiedStorageInstallationEvents {
        switch self {
        case .value(let events): return events
        }
    }
}

@MainActor
private final class ModifiedStorageCustomClassContent: ModifiedStorageObservedView, DynamicProperty {
    let events: ModifiedStorageInstallationEvents
    init(events: ModifiedStorageInstallationEvents) { self.events = events }

    nonisolated func update() {
        MainActor.assumeIsolated { events.entries.append("update:custom-class") }
    }
}

@MainActor
private enum ModifiedStorageCustomEnumContent: ModifiedStorageObservedView, DynamicProperty {
    case value(ModifiedStorageInstallationEvents)

    var events: ModifiedStorageInstallationEvents {
        switch self {
        case .value(let events): return events
        }
    }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { events.entries.append("update:custom-enum") }
    }
}

@MainActor
private struct ModifiedStorageAmbiguousContent: ModifiedStorageObservedView, DynamicProperty {
    let events: ModifiedStorageInstallationEvents
    private let ambiguous: Void = ()

    init(events: ModifiedStorageInstallationEvents) { self.events = events }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { events.entries.append("update:ambiguous") }
    }
}
