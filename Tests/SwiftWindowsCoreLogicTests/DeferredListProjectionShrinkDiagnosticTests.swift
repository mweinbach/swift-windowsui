import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Companion to the unchanged CanonicalViewBuilderMetadataTests regression.
/// Observations never request a build, frame, provider lookup, or admission check.
@MainActor
final class DeferredListProjectionShrinkDiagnosticTests: XCTestCase {
    func testPrebuiltRawArrayInListTaggedRowsKeepsFollowingMountedStateWhenOptionalDisappears() async throws {
        let model = ListShrinkDiagnosticModel()
        let recorder = ListShrinkDiagnosticRecorder()
        let capture = ListShrinkDiagnosticCapture(recorder: recorder)
        defer { recorder.emitReport() }
        var selection: String? = "element"
        let binding = Binding<String?>(get: { selection }, set: { selection = $0 })

        func currentRawArray() -> [AnyView] {
            let optional: ListShrinkDiagnosticTail? =
                model.includesOptional
                ? ListShrinkDiagnosticTail(name: "optional", seed: 3, capture: capture)
                : nil
            let tail = ListShrinkDiagnosticTail(name: "tail", seed: 7, capture: capture)
            return [AnyView(optional), AnyView(tail)]
        }

        let content = ListShrinkDiagnosticRoot(model: model) {
            capture.recordRootEntry()
            let previousBodies = capture.totalBodyCalls
            let prebuilt = currentRawArray()
            let list = List(["element"], id: \.self, selection: binding) { _ in
                capture.recordFactory()
                return prebuilt
            }
            capture.metadataBodyCounts.append((previousBodies, capture.totalBodyCalls))
            capture.recordRootReturn()
            return [AnyView(list)]
        }
        XCTAssertEqual(capture.totalBodyCalls, 0)
        XCTAssertEqual(capture.elementCalls, 0)
        let fixture = try ListShrinkDiagnosticWindow(content, capture: capture)
        defer { fixture.close() }
        let tail = try fixture.node("tail")
        let identity = try XCTUnwrap(tail.retainedViewIdentity)
        let tailBinding = try XCTUnwrap(capture.bindings["tail"])
        let optionalBinding = try XCTUnwrap(capture.bindings["optional"])
        XCTAssertEqual(tail.nodeTag, "element#1")
        XCTAssertEqual(tail.dynamicContentIndex, 0)
        XCTAssertEqual(tail.text, "7")

        capture.phase = .write41
        tailBinding.wrappedValue = 41
        fixture.snapshot(capture, checkpoint: .afterMutation)
        fixture.flush(capture)
        XCTAssertEqual(try fixture.node("tail").text, "41")
        let optionalBodies = capture.bodyCalls["optional", default: 0]

        capture.phase = .optionalRemoval
        model.includesOptional = false
        fixture.snapshot(capture, checkpoint: .afterMutation)
        fixture.flush(capture)

        let retained = try fixture.node("tail")
        XCTAssertTrue(retained === tail)
        XCTAssertEqual(retained.retainedViewIdentity, identity)
        XCTAssertEqual(retained.nodeTag, "element#0")
        XCTAssertEqual(retained.dynamicContentIndex, 0)
        XCTAssertEqual(retained.text, "41")
        XCTAssertEqual(tailBinding.wrappedValue, 41)
        XCTAssertTrue(fixture.nodes("optional").isEmpty)
        XCTAssertEqual(capture.bodyCalls["optional", default: 0], optionalBodies)

        capture.phase = .write42
        tailBinding.wrappedValue = 42
        fixture.snapshot(capture, checkpoint: .afterMutation)
        fixture.flush(capture)
        XCTAssertTrue(try fixture.node("tail") === tail)
        XCTAssertEqual(tail.text, "42")
        XCTAssertEqual(try XCTUnwrap(capture.bindings["tail"]).wrappedValue, 42)
        capture.phase = .retiredOptional99
        optionalBinding.wrappedValue = 99
        fixture.snapshot(capture, checkpoint: .afterMutation)
        fixture.flush(capture)
        XCTAssertEqual(optionalBinding.wrappedValue, 3)
        XCTAssertTrue(fixture.nodes("optional").isEmpty)
        XCTAssertGreaterThan(capture.elementCalls, 0)
        XCTAssertEqual(capture.elementCalls, capture.metadataBodyCounts.count)
        for counts in capture.metadataBodyCounts {
            XCTAssertEqual(counts.0, counts.1, "Normalizing raw arrays must not evaluate a custom body")
        }
    }
}

private enum ListShrinkDiagnosticPhase: String, Encodable {
    case initial, write41, optionalRemoval, write42, retiredOptional99
}

private enum ListShrinkDiagnosticCheckpoint: String, Encodable {
    case afterCreate, afterMutation, afterFrame
}

private struct ListShrinkDiagnosticListSnapshot: Encodable {
    let containerAddress: UInt
    let adapterAddress: UInt
    let actualChildCount: Int
    let actualChildAddresses: [UInt]
    let didTruncateChildAddresses: Bool
    let mappedRecordCount: Int
    let mappedLeafCount: Int
}

private struct ListShrinkDiagnosticSnapshot: Encodable {
    let checkpoint: ListShrinkDiagnosticCheckpoint
    let frameWithinFlush: Int
    // This host counter counts attempted reloads and excludes initial content.
    let noninitialRootReloadAttempts: Int
    // Existing native counter: incremented only after accepted row completion
    // and payload cleanup. It is not a count of accepted root reloads.
    let acceptedListResolutions: Int
    var visitedNodeCount = 0
    var didTruncateTraversal = false
    var listCount = 0
    var didTruncateLists = false
    var lists: [ListShrinkDiagnosticListSnapshot] = []
    var tailNodeCount = 0
    var firstTailAddress: UInt?
    var firstTailTextValue: Int?
    var optionalNodeCount = 0
}

private struct ListShrinkDiagnosticEvent: Encodable {
    enum Kind: String, Encodable { case rootEntry, rootReturn, rowFactory, body, snapshot }
    let sequence: Int
    let phase: ListShrinkDiagnosticPhase
    let kind: Kind
    let rootBodyCalls: Int
    let metadataSampleCount: Int
    let rowFactoryCalls: Int
    let totalBodyCalls: Int
    let tailBodyCalls: Int
    let optionalBodyCalls: Int
    let bodyName: String?
    let bodyValue: Int?
    let snapshot: ListShrinkDiagnosticSnapshot?
}

private struct ListShrinkDiagnosticReport: Encodable {
    let version = 1
    // Build provenance must come from the root runner; this is only the base.
    let baseSourceHead = "7db6b98095209e8fce07490277bfa556e9e6bcbd"
    let testClass = "DeferredListProjectionShrinkDiagnosticTests"
    let eventLimit = ListShrinkDiagnosticLimits.events
    let didDropEvents: Bool
    let events: [ListShrinkDiagnosticEvent]
}

private enum ListShrinkDiagnosticLimits {
    static let events = 128
    static let traversedNodes = 128
    static let lists = 4
    static let childAddresses = 16
}

@MainActor
private final class ListShrinkDiagnosticCapture {
    var bindings: [String: Binding<Int>] = [:]
    var bodyCalls: [String: Int] = [:]
    var totalBodyCalls = 0
    var elementCalls = 0
    var metadataBodyCounts: [(Int, Int)] = []
    var phase = ListShrinkDiagnosticPhase.initial
    private var rootBodyCalls = 0
    private let recorder: ListShrinkDiagnosticRecorder

    init(recorder: ListShrinkDiagnosticRecorder) { self.recorder = recorder }

    func recordRootEntry() {
        rootBodyCalls += 1
        record(.rootEntry)
    }

    func recordRootReturn() { record(.rootReturn) }

    func recordFactory() {
        elementCalls += 1
        record(.rowFactory)
    }

    func record(_ name: String, binding: Binding<Int>, value: Int) {
        bindings[name] = binding
        bodyCalls[name, default: 0] += 1
        totalBodyCalls += 1
        record(.body, bodyName: name, bodyValue: value)
    }

    func recordSnapshot(_ snapshot: ListShrinkDiagnosticSnapshot) {
        record(.snapshot, snapshot: snapshot)
    }

    private func record(
        _ kind: ListShrinkDiagnosticEvent.Kind, bodyName: String? = nil, bodyValue: Int? = nil,
        snapshot: ListShrinkDiagnosticSnapshot? = nil
    ) {
        recorder.record(
            kind, phase: phase, rootBodyCalls: rootBodyCalls,
            metadataSampleCount: metadataBodyCounts.count, rowFactoryCalls: elementCalls,
            totalBodyCalls: totalBodyCalls, tailBodyCalls: bodyCalls["tail", default: 0],
            optionalBodyCalls: bodyCalls["optional", default: 0],
            bodyName: bodyName, bodyValue: bodyValue, snapshot: snapshot)
    }
}

/// This object has no capture, binding, view, node, adapter, or callback field.
/// Only it is retained by the report defer after the original fixture closes.
@MainActor
private final class ListShrinkDiagnosticRecorder {
    private var events: [ListShrinkDiagnosticEvent] = []
    private var didDropEvents = false

    func record(
        _ kind: ListShrinkDiagnosticEvent.Kind, phase: ListShrinkDiagnosticPhase,
        rootBodyCalls: Int, metadataSampleCount: Int, rowFactoryCalls: Int, totalBodyCalls: Int,
        tailBodyCalls: Int, optionalBodyCalls: Int, bodyName: String?, bodyValue: Int?,
        snapshot: ListShrinkDiagnosticSnapshot?
    ) {
        guard events.count < ListShrinkDiagnosticLimits.events else {
            didDropEvents = true
            return
        }
        events.append(
            ListShrinkDiagnosticEvent(
                sequence: events.count + 1, phase: phase, kind: kind,
                rootBodyCalls: rootBodyCalls, metadataSampleCount: metadataSampleCount,
                rowFactoryCalls: rowFactoryCalls, totalBodyCalls: totalBodyCalls,
                tailBodyCalls: tailBodyCalls, optionalBodyCalls: optionalBodyCalls,
                bodyName: bodyName, bodyValue: bodyValue, snapshot: snapshot))
    }

    func emitReport() {
        // Emission runs after fixture.close(), never inside a build or frame.
        let report = ListShrinkDiagnosticReport(didDropEvents: didDropEvents, events: events)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(report)
            guard let line = String(data: data, encoding: .utf8) else {
                XCTFail("Could not decode the scalar List shrink diagnostic report")
                return
            }
            print("LIST_SHRINK_DIAGNOSTIC_V1 " + line)
        } catch {
            XCTFail("Could not encode the scalar List shrink diagnostic report")
        }
    }
}

@MainActor
private final class ListShrinkDiagnosticModel: ObservableObject {
    @Published var includesOptional = true
}

private struct ListShrinkDiagnosticRoot: View {
    @ObservedObject private var model: ListShrinkDiagnosticModel
    private let content: @MainActor () -> [AnyView]

    init(model: ListShrinkDiagnosticModel, content: @escaping @MainActor () -> [AnyView]) {
        self.model = model
        self.content = content
    }

    var body: [AnyView] {
        let _ = model.includesOptional
        return content()
    }
}

private struct ListShrinkDiagnosticTail: View {
    @State private var value: Int
    let name: String
    let capture: ListShrinkDiagnosticCapture

    init(name: String, seed: Int, capture: ListShrinkDiagnosticCapture) {
        self._value = State(initialValue: seed)
        self.name = name
        self.capture = capture
    }

    var body: some View {
        let current = value
        let _ = capture.record(name, binding: $value, value: current)
        Text(String(current)).accessibilityIdentifier(name)
    }
}

@MainActor
private final class ListShrinkDiagnosticWindow {
    private let host: WinSwiftUIWindowHost
    private let window: Win32Window
    private let clock: RuntimeTestClock

    init<Content: View>(_ content: Content, capture: ListShrinkDiagnosticCapture) throws {
        let configuration = WindowGroupConfiguration(
            title: "Canonical metadata state", size: IntSize(width: 400, height: 300), clearColor: .black,
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
        snapshot(capture, checkpoint: .afterCreate)
        flush(capture)
    }

    func flush(_ capture: ListShrinkDiagnosticCapture) {
        for frame in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
            snapshot(capture, checkpoint: .afterFrame, frameWithinFlush: frame + 1)
        }
    }

    /// Only scalar records escape this boundary. No node or adapter is kept
    /// across the next original mutation, frame, or fixture close.
    @inline(never)
    func snapshot(
        _ capture: ListShrinkDiagnosticCapture, checkpoint: ListShrinkDiagnosticCheckpoint,
        frameWithinFlush: Int = 0
    ) {
        var snapshot = ListShrinkDiagnosticSnapshot(
            checkpoint: checkpoint, frameWithinFlush: frameWithinFlush,
            noninitialRootReloadAttempts: host.executedReloadCount,
            acceptedListResolutions: host.hostedRuntime.lazyListResolveCount)
        collectSnapshot(in: host.hostedRuntime.root, into: &snapshot)
        capture.recordSnapshot(snapshot)
    }

    private func collectSnapshot(in node: ViewNode, into snapshot: inout ListShrinkDiagnosticSnapshot) {
        guard snapshot.visitedNodeCount < ListShrinkDiagnosticLimits.traversedNodes else {
            snapshot.didTruncateTraversal = true
            return
        }
        snapshot.visitedNodeCount += 1
        if let adapter = node.retainedLazyListAdapter {
            snapshot.listCount += 1
            if snapshot.lists.count < ListShrinkDiagnosticLimits.lists {
                snapshot.lists.append(
                    ListShrinkDiagnosticListSnapshot(
                        containerAddress: UInt(bitPattern: ObjectIdentifier(node)),
                        adapterAddress: UInt(bitPattern: ObjectIdentifier(adapter)),
                        actualChildCount: node.children.count,
                        actualChildAddresses: node.children.prefix(ListShrinkDiagnosticLimits.childAddresses).map {
                            UInt(bitPattern: ObjectIdentifier($0))
                        },
                        didTruncateChildAddresses: node.children.count > ListShrinkDiagnosticLimits.childAddresses,
                        mappedRecordCount: adapter.mountedRecordCount, mappedLeafCount: adapter.mountedLeafCount))
            } else {
                snapshot.didTruncateLists = true
            }
        }
        if node.accessibilityIdentifier == "tail" {
            snapshot.tailNodeCount += 1
            if snapshot.firstTailAddress == nil {
                snapshot.firstTailAddress = UInt(bitPattern: ObjectIdentifier(node))
                snapshot.firstTailTextValue = node.text.flatMap { Int($0) }
            }
        }
        if node.accessibilityIdentifier == "optional" { snapshot.optionalNodeCount += 1 }
        for child in node.children {
            guard snapshot.visitedNodeCount < ListShrinkDiagnosticLimits.traversedNodes else {
                snapshot.didTruncateTraversal = true
                break
            }
            collectSnapshot(in: child, into: &snapshot)
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

    private func allNodes(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { allNodes(in: $0) }
    }
}
