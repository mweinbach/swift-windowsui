import CUIAInterop
import Synchronization
@preconcurrency import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private let nativeItemLogicalID: UInt64 = 0x8000_0000_0000_1234
private let nativeItemInvalidArgument = Int32(bitPattern: 0x8007_0057)
private let nativeItemNotImplemented = Int32(bitPattern: 0x8000_4001)

private func nativeItemSurface(
    key: NativeWindowKey = NativeWindowKey(), revision: UInt64 = 7, sequence: UInt64 = 19,
    origin: Point = Point(x: 100, y: -40), scale: Double = 1.5
) -> NativeWindowSurface {
    let geometry = NativeWindowGeometry(
        revision: revision, nativeSequence: sequence, clientSize: IntSize(width: 480, height: 120),
        clientScreenOrigin: origin, scaleFactor: scale, effectiveScaleFactor: scale,
        monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
    return NativeWindowSurface(
        key: key, generation: 3, descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize),
        geometry: geometry)
}

private func nativeItemRoot() -> UIAElementSnapshot {
    UIAElementSnapshot(
        id: 0, parentID: nil, name: "Root", controlType: Int32(SWU_UIA_CONTROL_TYPE_GROUP),
        bounds: Rect(x: 0, y: 0, width: 320, height: 80), isEnabled: true,
        hasKeyboardFocus: false, isKeyboardFocusable: false, hasDefaultAction: false)
}

@MainActor
private class NativeItemTreeSource: UIAElementTreeSource {
    var root = nativeItemRoot()
    var snapshotGeometries: [NativeWindowGeometry] = []
    var legacySnapshotReads = 0

    @MainActor init() {}

    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        legacySnapshotReads += 1
        return [root]
    }

    func uiaElementSnapshots(geometry: NativeWindowGeometry) throws -> [UIAElementSnapshot] {
        snapshotGeometries.append(geometry)
        return [root]
    }

    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool { false }
    func uiaSetFocus(elementID: UInt64) {}
}

@MainActor
private final class NativeItemSource: NativeItemTreeSource, UIAItemContainerSource {
    var lookupResult = UIAItemContainerResult.item(nativeItemLogicalID)
    var lookupGeometries: [NativeWindowGeometry] = []
    var starts: [UInt64?] = []
    var logicalReads: [UInt64] = []
    var legacyLookupReads = 0
    var onLookup: (() -> Void)?

    override init() {
        super.init()
        root.supportsItemContainer = true
    }

    func uiaFindItem(containerID: UInt64, afterElementID: UInt64?) -> UIAItemContainerResult {
        legacyLookupReads += 1
        return lookupResult
    }

    func uiaFindItem(
        containerID: UInt64, afterElementID: UInt64?, geometry: NativeWindowGeometry
    ) throws -> UIAItemContainerResult {
        lookupGeometries.append(geometry)
        starts.append(afterElementID)
        onLookup?()
        return lookupResult
    }

    func uiaLogicalItemState(elementID: UInt64) -> UIALogicalItemState {
        logicalReads.append(elementID)
        return elementID == nativeItemLogicalID ? .placeholder : .ordinary
    }
}

@MainActor
private final class NativeItemLegacySource: NativeItemTreeSource, UIAItemContainerSource {
    var lookupReads = 0

    override init() {
        super.init()
        root.supportsItemContainer = true
    }

    func uiaFindItem(containerID: UInt64, afterElementID: UInt64?) -> UIAItemContainerResult {
        lookupReads += 1
        return .end
    }

    func uiaLogicalItemState(elementID: UInt64) -> UIALogicalItemState { .ordinary }
}

private final class NativeItemSnapshots: NativeWindowSnapshotSource {
    private let value: Mutex<NativeWindowSurface>
    init(_ surface: NativeWindowSurface) { value = Mutex(surface) }
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { value.withLock { .success($0) } }
    func publish(_ surface: NativeWindowSurface) { value.withLock { $0 = surface } }
}

/// These tests deliberately have no native owner that could make progress.
/// Any attempted command is observed and rejected, never silently executed.
private final class NativeItemCommands: NativeWindowCommandSink {
    private let submitted = Mutex(0)
    var count: Int { submitted.withLock { $0 } }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        submitted.withLock { $0 += 1 }
        let failure = NativeWindowOwnerFailure.execution("No native owner in the ItemContainer fixture")
        command.reject(failure)
        return .rejected(failure)
    }
}

private final class NativeItemEffects: Sendable {
    private struct Counts {
        var calls = 0
        var wakes = 0
    }
    private let counts = Mutex(Counts())
    var calls: Int { counts.withLock { $0.calls } }
    var wakes: Int { counts.withLock { $0.wakes } }
    private func recordCall() { counts.withLock { $0.calls += 1 } }
    func wake() -> Result<Void, NativeWindowOwnerFailure> {
        counts.withLock { $0.wakes += 1 }
        return .success(())
    }

    func makeCalls() -> UIANativeCalls {
        UIANativeCalls(
            clientsAreListening: { [self] in
                recordCall()
                return false
            },
            returnProvider: { [self] _, _, _, _ in
                recordCall()
                return 0
            },
            disconnectProvider: { [self] _ in
                recordCall()
                return 0
            },
            raiseFocusChanged: { [self] _ in recordCall() },
            raiseStructureChanged: { [self] _ in recordCall() },
            raiseLiveRegionChanged: { [self] _ in recordCall() })
    }
}

private final class NativeItemContext: NativeWindowOwnerContext {
    let surface: NativeWindowSurface
    let snapshotSource: any NativeWindowSnapshotSource
    let wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure>
    private var attachments: [NativeWindowAttachmentID: any NativeWindowOwnerAttachment] = [:]

    init(surface: NativeWindowSurface, snapshots: NativeItemSnapshots, effects: NativeItemEffects) {
        self.surface = surface
        snapshotSource = snapshots
        wake = { effects.wake() }
    }
    func attachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? { attachments[id] }
    func install(_ attachment: any NativeWindowOwnerAttachment, for id: NativeWindowAttachmentID) throws {
        guard attachments[id] == nil else { throw NativeWindowOwnerFailure.duplicateAttachment(id) }
        attachments[id] = attachment
    }
    func removeAttachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? {
        attachments.removeValue(forKey: id)
    }
    func withNativeModal<Result>(_ body: () throws -> Result) rethrows -> Result { try body() }
}

/// The production Swift callback table and real local C provider vtables are
/// used, with copied geometry and injected native effects. No HWND or UIA
/// client, COM activation, message pump, or renderer is created by this fixture.
@MainActor
private final class NativeItemFixture {
    let effects = NativeItemEffects()
    let commands = NativeItemCommands()
    let surface: NativeWindowSurface
    let snapshots: NativeItemSnapshots
    let context: NativeItemContext
    var bridge: UIAProviderBridge?
    var attachment: UIANativeProviderAttachment?
    var root: UnsafeMutableRawPointer?
    var admittedGeometries: [NativeWindowGeometry] = []
    var beforeRequest: ((NativeWindowGeometry) -> Result<Void, NativeWindowOwnerFailure>)?
    private var attachmentID: NativeWindowAttachmentID?

    init(source: any UIAElementTreeSource) throws {
        surface = nativeItemSurface()
        snapshots = NativeItemSnapshots(surface)
        context = NativeItemContext(surface: surface, snapshots: snapshots, effects: effects)
        let bridge = UIAProviderBridge(
            source: source, nativeWindowKey: surface.key, nativeSnapshotSource: snapshots,
            nativeCommandSink: commands,
            beforeRequest: { [weak self] key, generation, geometry in
                guard let self else { return .failure(.closed) }
                guard key == surface.key else { return .failure(.staleWindow) }
                guard generation == surface.generation else {
                    return .failure(.staleSurface(expected: generation, actual: surface.generation))
                }
                admittedGeometries.append(geometry)
                return beforeRequest?(geometry) ?? .success(())
            })
        self.bridge = bridge
        let factory = try XCTUnwrap(bridge.makeNativeAttachmentFactory(nativeCalls: effects.makeCalls()))
        let attachment = try XCTUnwrap(try factory.makeAttachment(in: context) as? UIANativeProviderAttachment)
        self.attachment = attachment
        attachmentID = factory.attachmentID
        try context.install(attachment, for: factory.attachmentID)
        root = try XCTUnwrap(attachment.retainedRootProviderForTesting())
    }

    func close() {
        beforeRequest = nil
        bridge?.revokeNativeRequests()
        _ = attachment?.detach()
        SWU_UIAReleaseProvider(root)
        root = nil
        if let attachmentID { _ = context.removeAttachment(for: attachmentID) }
        attachmentID = nil
        attachment = nil
        bridge = nil
    }
}

private func nativeItemFind(
    _ pattern: UnsafeMutableRawPointer?, after: UnsafeMutableRawPointer? = nil,
    property: Int32 = Int32(SWU_UIA_ITEM_PROPERTY_ANY)
) -> (status: Int32, provider: UnsafeMutableRawPointer?) {
    var result: UnsafeMutableRawPointer?
    let status = SWU_UIAItemContainerProviderFindItemResult(pattern, after, property, nil, 0, &result)
    return (status, result)
}

private func nativeItemRuntimeID(_ provider: UnsafeMutableRawPointer?) -> (status: Int32, values: [Int32]) {
    var values = [Int32](repeating: 0, count: 8)
    var count: Int32 = 0
    let status = values.withUnsafeMutableBufferPointer {
        SWU_UIAProviderGetRuntimeIdResult(provider, $0.baseAddress, Int32($0.count), &count)
    }
    return (status, Array(values.prefix(Int(max(0, count)))))
}

private func nativeItemName(_ provider: UnsafeMutableRawPointer?) -> (status: Int32, name: String?) {
    var text: UnsafeMutablePointer<UInt16>?
    let status = SWU_UIAProviderGetNameResult(provider, &text)
    guard let text else { return (status, nil) }
    defer { SWU_UIAFreeString(text) }
    return (status, String(decodingCString: text, as: UTF16.self))
}

private func nativeItemNavigate(
    _ provider: UnsafeMutableRawPointer, direction: Int32, firstFailure: inout String?
) -> UnsafeMutableRawPointer? {
    var result: UnsafeMutableRawPointer?
    let status = SWU_UIAProviderNavigateResult(provider, direction, &result)
    if status < 0, firstFailure == nil { firstFailure = "Navigate(\(direction)) HRESULT \(status)" }
    return result
}

private func nativeItemFindPattern(
    in provider: UnsafeMutableRawPointer?, firstFailure: inout String?
) -> UnsafeMutableRawPointer? {
    guard let provider else { return nil }
    var pattern: UnsafeMutableRawPointer?
    let status = SWU_UIAProviderGetPatternResult(provider, Int32(SWU_UIA_PATTERN_ITEM_CONTAINER), &pattern)
    if status < 0, firstFailure == nil { firstFailure = "GetPatternProvider(ItemContainer) HRESULT \(status)" }
    if let pattern { return pattern }
    var next = nativeItemNavigate(provider, direction: Int32(SWU_UIA_NAV_FIRST_CHILD), firstFailure: &firstFailure)
    while let child = next {
        let pattern = nativeItemFindPattern(in: child, firstFailure: &firstFailure)
        next =
            pattern == nil
            ? nativeItemNavigate(child, direction: Int32(SWU_UIA_NAV_NEXT_SIBLING), firstFailure: &firstFailure) : nil
        SWU_UIAReleaseProvider(child)
        if let pattern { return pattern }
    }
    return nil
}

@MainActor
private final class NativeItemRows {
    var rows = Array(0..<1_000)
    var factories: [Int] = []
    var activations: [Int] = []
    var legacyMappings = 0

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        return [AnyView(Button("Row \(id)") { [weak self] in self?.activations.append(id) }.frame(height: 24))]
    }
}

@MainActor
private final class NativeItemRuntimeFixture {
    let rows = NativeItemRows()
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let native: NativeItemFixture
    private(set) var itemContainer: UnsafeMutableRawPointer?

    init() throws {
        let rows = rows
        host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(rows.rows, id: \.self) { rows.makeRows($0) }.listStyle(.plain)
        }
        source = RuntimeUIAElementTreeSource(runtime: host.runtime) { bounds in
            rows.legacyMappings += 1
            XCTFail("Native ItemContainer work must never invoke the legacy screen mapper")
            return bounds
        }
        XCTAssertNotNil(host.layout())
        native = try NativeItemFixture(source: source)
        do {
            var firstFailure: String?
            itemContainer = try XCTUnwrap(
                nativeItemFindPattern(in: native.root, firstFailure: &firstFailure),
                itemContainerFailureDetails(firstFailure: firstFailure))
        } catch {
            native.close()
            host.close()
            throw error
        }
    }

    /// Evaluated only by a failed unwrap. These reads do not project, settle
    /// layout, enumerate logical rows, or invoke authored callbacks.
    private func itemContainerFailureDetails(firstFailure: String?) -> String {
        let lists = host.lists
        let adapters = lists.map { node in
            guard let adapter = node.retainedLazyListAdapter else { return "missing adapter" }
            let managedCurrent = adapter.managedLogicalDescriptorBinding.map { $0.isCurrent }
            return "logicalCurrent=\(adapter.hasCurrentLogicalSnapshot), "
                + "managedCurrent=\(String(describing: managedCurrent))"
        }
        return "ItemContainer discovery failed: firstNativeFailure=\(String(describing: firstFailure)), "
            + "lastNativeFailure=\(String(describing: native.bridge?.lastNativeFailure)), "
            + "lists=\(lists.count), factories=\(rows.factories.count), adapters=\(adapters)"
    }

    func close() {
        SWU_UIAReleaseProvider(itemContainer)
        itemContainer = nil
        native.close()
        host.close()
    }

    func item(at index: Int) throws -> UnsafeMutableRawPointer {
        var current: UnsafeMutableRawPointer?
        for _ in 0...index {
            let previous = current
            current = nil
            defer { SWU_UIAReleaseProvider(previous) }
            let next = nativeItemFind(itemContainer, after: previous)
            XCTAssertEqual(next.status, 0)
            current = try XCTUnwrap(next.provider)
        }
        return try XCTUnwrap(current)
    }

    func elementID(_ provider: UnsafeMutableRawPointer) throws -> UInt64 {
        let identity = nativeItemRuntimeID(provider)
        XCTAssertEqual(identity.status, 0)
        let low = UInt64(UInt32(bitPattern: try XCTUnwrap(identity.values.dropFirst().first)))
        let high = identity.values.count > 2 ? UInt64(UInt32(bitPattern: identity.values[2])) << 32 : 0
        return high | low
    }
}

@MainActor
final class UIANativeItemContainerIntegrationTests: XCTestCase {
    func testOptionalLogicalCapabilityPreservesOrdinaryQueryCounts() async throws {
        let ordinary = NativeItemTreeSource()
        let ordinaryFixture = try NativeItemFixture(source: ordinary)
        defer { ordinaryFixture.close() }
        XCTAssertEqual(nativeItemName(ordinaryFixture.root).name, "Root")
        XCTAssertEqual(ordinaryFixture.admittedGeometries.count, 1)
        XCTAssertEqual(ordinary.snapshotGeometries.count, 1)

        let logical = NativeItemSource()
        let logicalFixture = try NativeItemFixture(source: logical)
        defer { logicalFixture.close() }
        XCTAssertEqual(nativeItemName(logicalFixture.root).name, "Root")
        XCTAssertEqual(logical.logicalReads, [0, 0])
        XCTAssertEqual(logicalFixture.admittedGeometries.count, 3)
        XCTAssertEqual(logical.snapshotGeometries.count, 1)
        XCTAssertEqual(ordinary.legacySnapshotReads, 0)
        XCTAssertEqual(logical.legacySnapshotReads, 0)
        XCTAssertEqual(ordinaryFixture.commands.count + logicalFixture.commands.count, 0)
    }

    func testNativeLookupPreservesTypedOutcomesAndHighRuntimeIdentity() async throws {
        let source = NativeItemSource()
        let fixture = try NativeItemFixture(source: source)
        defer { fixture.close() }
        let pattern = try XCTUnwrap(SWU_UIAProviderGetItemContainerPattern(fixture.root))
        defer { SWU_UIAReleaseProvider(pattern) }
        let found = nativeItemFind(pattern)
        defer { SWU_UIAReleaseProvider(found.provider) }
        XCTAssertEqual(found.status, 0)
        let provider = try XCTUnwrap(found.provider)
        let identity = nativeItemRuntimeID(provider)
        XCTAssertEqual(identity.status, 0)
        XCTAssertEqual(identity.values, [0x5357, 0x1234, Int32(bitPattern: 0x8000_0000)])

        for (lookup, expected) in [
            (UIAItemContainerResult.end, Int32(0)), (.invalidStart, nativeItemInvalidArgument),
            (.unavailable, UIANativeHRESULT.elementNotAvailable),
        ] {
            source.lookupResult = lookup
            let result = nativeItemFind(pattern, after: provider)
            defer { SWU_UIAReleaseProvider(result.provider) }
            XCTAssertEqual(result.status, expected)
            XCTAssertNil(result.provider)
        }
        XCTAssertEqual(source.starts, [nil, nativeItemLogicalID, nativeItemLogicalID, nativeItemLogicalID])
        XCTAssertEqual(source.legacyLookupReads, 0)
        XCTAssertEqual(fixture.commands.count, 0)
    }

    func testLookupFlushesCopiedSequenceAndUsesFreshGeometryWithoutNativeProgress() async throws {
        let source = NativeItemSource()
        let fixture = try NativeItemFixture(source: source)
        defer { fixture.close() }
        let pattern = try XCTUnwrap(SWU_UIAProviderGetItemContainerPattern(fixture.root))
        defer { SWU_UIAReleaseProvider(pattern) }
        source.lookupResult = .unavailable
        fixture.beforeRequest = { geometry in
            if geometry.nativeSequence == 91 { source.lookupResult = .item(nativeItemLogicalID) }
            return .success(())
        }
        let firstSurface = nativeItemSurface(key: fixture.surface.key, revision: 12, sequence: 91)
        fixture.snapshots.publish(firstSurface)
        fixture.admittedGeometries = []
        let first = nativeItemFind(pattern)
        defer { SWU_UIAReleaseProvider(first.provider) }
        XCTAssertEqual(first.status, 0)
        XCTAssertNotNil(first.provider)
        XCTAssertFalse(fixture.admittedGeometries.isEmpty)
        XCTAssertTrue(fixture.admittedGeometries.allSatisfy { $0 == firstSurface.geometry })
        XCTAssertEqual(source.lookupGeometries, [firstSurface.geometry])

        fixture.beforeRequest = nil
        source.lookupResult = .end
        let secondSurface = nativeItemSurface(
            key: fixture.surface.key, revision: 13, sequence: 94, origin: Point(x: 800, y: 400), scale: 2)
        fixture.snapshots.publish(secondSurface)
        let second = nativeItemFind(pattern, after: first.provider)
        defer { SWU_UIAReleaseProvider(second.provider) }
        XCTAssertEqual(second.status, 0)
        XCTAssertNil(second.provider)
        XCTAssertEqual(source.lookupGeometries, [firstSurface.geometry, secondSurface.geometry])
        XCTAssertEqual(source.legacyLookupReads, 0)
        XCTAssertEqual(source.legacySnapshotReads, 0)
        XCTAssertEqual(fixture.commands.count, 0)
        XCTAssertEqual(fixture.effects.calls, 0)
    }

    func testUnsupportedNativeSearchNeverReachesLookupOrProjection() async throws {
        let source = NativeItemSource()
        let fixture = try NativeItemFixture(source: source)
        defer { fixture.close() }
        let pattern = try XCTUnwrap(SWU_UIAProviderGetItemContainerPattern(fixture.root))
        defer { SWU_UIAReleaseProvider(pattern) }
        let projections = source.snapshotGeometries.count
        for property in [SWU_UIA_ITEM_PROPERTY_NAME, SWU_UIA_ITEM_PROPERTY_AUTOMATION_ID] {
            let result = nativeItemFind(pattern, property: Int32(property))
            defer { SWU_UIAReleaseProvider(result.provider) }
            XCTAssertEqual(result.status, nativeItemNotImplemented)
            XCTAssertNil(result.provider)
        }
        XCTAssertTrue(source.lookupGeometries.isEmpty)
        XCTAssertEqual(source.snapshotGeometries.count, projections)
        XCTAssertEqual(source.legacyLookupReads, 0)
    }

    func testNestedLookupAndAdmissionFailureDoNotBecomeSuccessfulPayloads() async throws {
        let source = NativeItemSource()
        let fixture = try NativeItemFixture(source: source)
        defer { fixture.close() }
        let pattern = try XCTUnwrap(SWU_UIAProviderGetItemContainerPattern(fixture.root))
        defer { SWU_UIAReleaseProvider(pattern) }
        var nested: (status: Int32, provider: UnsafeMutableRawPointer?)?
        source.onLookup = { nested = nativeItemFind(pattern) }
        let outer = nativeItemFind(pattern)
        defer {
            SWU_UIAReleaseProvider(outer.provider)
            SWU_UIAReleaseProvider(nested?.provider)
        }
        XCTAssertEqual(outer.status, 0)
        XCTAssertNotNil(outer.provider)
        XCTAssertEqual(nested?.status, UIANativeHRESULT.failed)
        XCTAssertNil(nested?.provider)
        XCTAssertEqual(source.lookupGeometries.count, 1)

        source.onLookup = nil
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputRecords", limit: 1)
        fixture.beforeRequest = { _ in .failure(failure) }
        let failed = nativeItemFind(pattern)
        defer { SWU_UIAReleaseProvider(failed.provider) }
        XCTAssertEqual(failed.status, UIANativeHRESULT.failed)
        XCTAssertNil(failed.provider)
        XCTAssertEqual(fixture.bridge?.lastNativeFailure, failure)
        XCTAssertEqual(source.lookupGeometries.count, 1)
        XCTAssertEqual(fixture.commands.count, 0)
    }

    func testRevocationInsideLookupRejectsFoundOutputAndDrainsAfterFullCall() async throws {
        let source = NativeItemSource()
        let fixture = try NativeItemFixture(source: source)
        defer { fixture.close() }
        let pattern = try XCTUnwrap(SWU_UIAProviderGetItemContainerPattern(fixture.root))
        defer { SWU_UIAReleaseProvider(pattern) }
        var quiescentInside: Bool?
        source.onLookup = { [weak fixture] in
            fixture?.bridge?.revokeNativeRequests()
            quiescentInside = fixture?.attachment?.isQuiescent
        }
        let result = nativeItemFind(pattern)
        defer { SWU_UIAReleaseProvider(result.provider) }
        XCTAssertEqual(result.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(result.provider)
        XCTAssertEqual(quiescentInside, false)
        XCTAssertEqual(fixture.attachment?.isQuiescent, true)
        XCTAssertEqual(fixture.effects.wakes, 1)
        XCTAssertEqual(fixture.effects.calls, 0)
    }

    func testLegacyOnlyLookupFailsExplicitlyOnNativeRouteWithoutCallingFallback() async throws {
        let source = NativeItemLegacySource()
        let fixture = try NativeItemFixture(source: source)
        defer { fixture.close() }
        let pattern = try XCTUnwrap(SWU_UIAProviderGetItemContainerPattern(fixture.root))
        defer { SWU_UIAReleaseProvider(pattern) }
        let result = nativeItemFind(pattern)
        defer { SWU_UIAReleaseProvider(result.provider) }
        XCTAssertEqual(result.status, UIANativeHRESULT.failed)
        XCTAssertNil(result.provider)
        XCTAssertEqual(source.lookupReads, 0)
        XCTAssertThrowsError(
            try source.uiaFindItem(containerID: 0, afterElementID: nil, geometry: fixture.surface.geometry)
        ) { XCTAssertEqual($0 as? UIAProviderRequestFailure, .unsupportedNativeItemLookup) }
        XCTAssertEqual(source.uiaFindItem(containerID: 0, afterElementID: nil), .end)
        XCTAssertEqual(source.lookupReads, 1, "The explicit legacy entry retains its existing semantics")
    }

    func testRuntimeGeometryLookupTakesFreshSnapshotAndNeverUsesLegacyMapper() async throws {
        let fixture = try NativeItemRuntimeFixture()
        defer { fixture.close() }
        let geometry = fixture.native.surface.geometry
        let snapshots = try fixture.source.uiaElementSnapshots(geometry: geometry)
        let container = try XCTUnwrap(snapshots.first(where: \.supportsItemContainer))
        let factories = fixture.rows.factories
        let first = try fixture.source.uiaFindItem(containerID: container.id, afterElementID: nil, geometry: geometry)
        guard case .item = first else { return XCTFail("Expected a current logical List identity") }
        var invalid = geometry
        invalid.effectiveScaleFactor = 0
        invalid.scaleFactor = 0
        XCTAssertThrowsError(
            try fixture.source.uiaFindItem(containerID: container.id, afterElementID: nil, geometry: invalid)
        ) { XCTAssertEqual($0 as? UIAProviderRequestFailure, .invalidGeometry) }
        XCTAssertEqual(fixture.rows.legacyMappings, 0)
        XCTAssertEqual(fixture.rows.factories, factories)
        XCTAssertEqual(fixture.native.commands.count, 0)
    }

    func testNativeRuntimeIDAndRealizeRespectPendingAcceptedReplacement() async throws {
        let fixture = try NativeItemRuntimeFixture()
        defer { fixture.close() }
        let row = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(row) }
        let identity = nativeItemRuntimeID(row)
        XCTAssertEqual(identity.status, 0)
        XCTAssertEqual(identity.values.count, 3)
        let element = try fixture.elementID(row)
        let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(row))
        defer { SWU_UIAReleaseProvider(pattern) }
        let witness = try XCTUnwrap(fixture.host.runtime.lazyListAccessibilityItem(in: try fixture.host.list()))

        fixture.host.reload()
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: witness))
        let factories = fixture.rows.factories
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: element), .placeholder)
        XCTAssertEqual(nativeItemRuntimeID(row).values, identity.values)
        XCTAssertEqual(fixture.rows.factories, factories)
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: witness))

        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), 0)
        XCTAssertTrue(fixture.rows.factories.contains(300))
        XCTAssertLessThan(fixture.rows.factories.count - factories.count, 128)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: element), .ordinary)
        XCTAssertEqual(nativeItemName(row).name, "Row 300")
        XCTAssertEqual(nativeItemRuntimeID(row).values, identity.values)
        XCTAssertEqual(fixture.rows.legacyMappings, 0)
        XCTAssertEqual(fixture.native.commands.count, 0)
        XCTAssertTrue(fixture.rows.activations.isEmpty)
    }

    func testNativeDeletedTokenCannotBorrowPendingReplacementOrPrepareRows() async throws {
        let fixture = try NativeItemRuntimeFixture()
        defer { fixture.close() }
        let row = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(row) }
        let element = try fixture.elementID(row)
        let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(row))
        defer { SWU_UIAReleaseProvider(pattern) }
        let witness = try XCTUnwrap(fixture.host.runtime.lazyListAccessibilityItem(in: try fixture.host.list()))
        fixture.rows.rows.removeAll { $0 == 300 }
        fixture.host.reload()
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: witness))
        let factories = fixture.rows.factories
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: element), .unavailable)
        let identity = nativeItemRuntimeID(row)
        XCTAssertEqual(identity.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertTrue(identity.values.isEmpty)
        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), UIANativeHRESULT.elementNotAvailable)
        XCTAssertEqual(fixture.rows.factories, factories)
        XCTAssertEqual(fixture.rows.legacyMappings, 0)
        XCTAssertEqual(fixture.native.commands.count, 0)
    }
}
