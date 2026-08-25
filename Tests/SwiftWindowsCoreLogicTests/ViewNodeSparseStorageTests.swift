import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A retained tree contains far more text/layout nodes than controls. Rare
/// handlers and Charts metadata must therefore remain genuinely sparse: an
/// innocent getter, nil assignment, or reconciliation cannot silently put the
/// former sixty-three inline fields back into every node.
@MainActor
final class ViewNodeSparseStorageTests: XCTestCase {
    func testOrdinaryNodeDoesNotAllocateOptionalCapabilityStorage() async {
        let node = ViewNode()

        XCTAssertFalse(node.hasAllocatedInteractionHandlers)
        XCTAssertFalse(node.hasAllocatedDropHandlers)
        XCTAssertFalse(node.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(node.hasAllocatedChartMetadata)

        XCTAssertNil(node.onPointerDown)
        XCTAssertNil(node.onKeyDown)
        XCTAssertNil(node.onIMEComposition)
        XCTAssertNil(node.onDeleteRows)
        XCTAssertNil(node.onMakeDragPayload)
        XCTAssertNil(node.onLayout)
        XCTAssertNil(node.geometryReaderBuild)
        XCTAssertNil(node.chartXAxis)
        XCTAssertNil(node.chartScrollPositionY)

        node.onActivate = nil
        node.onDropRows = nil
        node.onAppear = nil
        node.chartLegend = nil

        XCTAssertFalse(node.hasAllocatedInteractionHandlers)
        XCTAssertFalse(node.hasAllocatedDropHandlers)
        XCTAssertFalse(node.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(node.hasAllocatedChartMetadata)
    }

    func testRareCallbacksAndChartFieldsAreNotStoredInlineOnEveryNode() async {
        let node = ViewNode()
        let inlineFields = Set(Mirror(reflecting: node).children.compactMap(\.label))

        XCTAssertTrue(inlineFields.contains("interactionHandlers"))
        XCTAssertTrue(inlineFields.contains("dropHandlers"))
        XCTAssertTrue(inlineFields.contains("lifecycleHandlers"))
        XCTAssertTrue(inlineFields.contains("chartMetadata"))

        for removedInlineField in [
            "onPointerEnter", "onKeyDown", "onIMEComposition", "textInputCaretRectProvider",
            "onDeleteRows", "onDropRows", "onMakeDragPayload", "onLayout", "onAppear",
            "geometryReaderBuild", "chartXAxis", "chartLegend", "chartScrollPositionY",
        ] {
            XCTAssertFalse(
                inlineFields.contains(removedInlineField),
                "\(removedInlineField) must stay in optional capability storage, not on every ViewNode"
            )
        }
    }

    func testInteractionCallbacksAllocateOnlyTheirOwnStorageAndRemainCallable() async {
        let node = ViewNode()
        var events: [String] = []

        node.onPointerDown = { events.append("pointer") }
        node.onActivate = { events.append("activate") }
        node.onKeyDown = { event in events.append("key:\(event.keyCode)") }

        XCTAssertTrue(node.hasAllocatedInteractionHandlers)
        XCTAssertFalse(node.hasAllocatedDropHandlers)
        XCTAssertFalse(node.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(node.hasAllocatedChartMetadata)

        node.onPointerDown?()
        node.onActivate?()
        node.onKeyDown?(KeyboardEvent(keyCode: 65))
        XCTAssertEqual(events, ["pointer", "activate", "key:65"])

        node.onActivate = nil
        XCTAssertNil(node.onActivate)
        XCTAssertNotNil(node.onPointerDown)
    }

    func testDropCallbacksAllocateIndependentlyAndPreservePayloads() async {
        let node = ViewNode()
        var droppedValues: [String] = []
        var droppedOffset = -1

        node.onDropRows = { payloads, offset in
            droppedValues = payloads.compactMap { $0 as? String }
            droppedOffset = offset
        }
        node.onMakeDragPayload = { "drag-value" }

        XCTAssertFalse(node.hasAllocatedInteractionHandlers)
        XCTAssertTrue(node.hasAllocatedDropHandlers)
        XCTAssertFalse(node.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(node.hasAllocatedChartMetadata)

        node.onDropRows?(["alpha", "beta"], 7)
        XCTAssertEqual(droppedValues, ["alpha", "beta"])
        XCTAssertEqual(droppedOffset, 7)
        XCTAssertEqual(node.onMakeDragPayload?() as? String, "drag-value")
    }

    func testLifecycleCallbacksAllocateIndependentlyAndReceiveGeometry() async {
        let node = ViewNode()
        var observedFrame: Rect?
        var didAppear = false

        node.onLayout = { observedFrame = $0 }
        node.onAppearWithNode = { appearedNode in didAppear = appearedNode === node }

        XCTAssertFalse(node.hasAllocatedInteractionHandlers)
        XCTAssertFalse(node.hasAllocatedDropHandlers)
        XCTAssertTrue(node.hasAllocatedLifecycleHandlers)
        XCTAssertFalse(node.hasAllocatedChartMetadata)

        let frame = Rect(x: 4, y: 8, width: 120, height: 32)
        node.onLayout?(frame)
        node.onAppearWithNode?(node)

        XCTAssertEqual(observedFrame, frame)
        XCTAssertTrue(didAppear)
    }

    func testChartInitializerAndMutationsAllocateOnlyChartMetadata() async {
        let node = ViewNode(
            chartXAxis: "time",
            chartYScale: "linear",
            chartLegend: "visible",
            chartScrollPositionY: "42"
        )

        XCTAssertFalse(node.hasAllocatedInteractionHandlers)
        XCTAssertFalse(node.hasAllocatedDropHandlers)
        XCTAssertFalse(node.hasAllocatedLifecycleHandlers)
        XCTAssertTrue(node.hasAllocatedChartMetadata)
        XCTAssertEqual(node.chartXAxis, "time")
        XCTAssertEqual(node.chartYScale, "linear")
        XCTAssertEqual(node.chartLegend, "visible")
        XCTAssertEqual(node.chartScrollPositionY, "42")
        XCTAssertNil(node.chartXSelection)

        node.chartXSelection = "row-9"
        node.chartLegend = nil

        XCTAssertEqual(node.chartXSelection, "row-9")
        XCTAssertNil(node.chartLegend)
        XCTAssertEqual(node.chartXAxis, "time")
    }

    func testReconciliationRefreshesIMEHandlersAndCaretGeometryProviders() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let host = ComponentHost(runtime: runtime)
        var generation = 1
        var compositionGenerations: [Int] = []

        host.setComponents {
            [
                Component(key: "editor") { _ in
                    let node = ViewNode()
                    let capturedGeneration = generation
                    if capturedGeneration < 3 {
                        node.onIMEComposition = { _ in
                            compositionGenerations.append(capturedGeneration)
                        }
                        node.textInputCaretRectProvider = {
                            Rect(x: Double(capturedGeneration), y: 4, width: 2, height: 18)
                        }
                    }
                    return node
                }
            ]
        }

        let retained = try XCTUnwrap(runtime.root.children.first)
        retained.onIMEComposition?(IMECompositionEvent(phase: .updated("first")))
        XCTAssertEqual(retained.textInputCaretRectProvider?()?.origin.x, 1)

        generation = 2
        host.reload()

        XCTAssertTrue(runtime.root.children.first === retained)
        retained.onIMEComposition?(IMECompositionEvent(phase: .updated("second")))
        XCTAssertEqual(compositionGenerations, [1, 2])
        XCTAssertEqual(retained.textInputCaretRectProvider?()?.origin.x, 2)

        generation = 3
        host.reload()

        XCTAssertNil(retained.onIMEComposition)
        XCTAssertNil(retained.textInputCaretRectProvider)
    }

    func testReconciliationCopiesAndClearsSparseChartMetadata() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let host = ComponentHost(runtime: runtime)
        var legend: String? = "initial"

        host.setComponents {
            [
                Component(key: "chart") { _ in
                    ViewNode(chartXAxis: legend == nil ? nil : "time", chartLegend: legend)
                }
            ]
        }

        let retained = try XCTUnwrap(runtime.root.children.first)
        XCTAssertEqual(retained.chartLegend, "initial")

        legend = "updated"
        host.reload()
        XCTAssertTrue(runtime.root.children.first === retained)
        XCTAssertEqual(retained.chartLegend, "updated")
        XCTAssertEqual(retained.chartXAxis, "time")

        legend = nil
        host.reload()
        XCTAssertNil(retained.chartLegend)
        XCTAssertNil(retained.chartXAxis)
    }

    func testLongLazyListRowsDoNotAllocateRareCapabilityStorage() async {
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<500, id: \.self) { index in
                        Text("row \(index)").frame(width: 220, height: 24)
                    }
                }
            },
            size: IntSize(width: 240, height: 200),
            displayScale: 1
        )

        var allNodes: [ViewNode] = []
        func visit(_ node: ViewNode) {
            allNodes.append(node)
            node.children.forEach(visit)
        }
        visit(snapshot.runtime.root)

        XCTAssertGreaterThan(allNodes.count, 500)
        XCTAssertLessThan(
            allNodes.filter(\.hasAllocatedInteractionHandlers).count,
            12,
            "scroll chrome may handle input, but text/layout rows must not allocate interaction bags"
        )
        XCTAssertEqual(allNodes.filter(\.hasAllocatedDropHandlers).count, 0)
        XCTAssertLessThan(
            allNodes.filter(\.hasAllocatedLifecycleHandlers).count,
            12,
            "list layout itself must not allocate lifecycle callbacks for every ordinary row"
        )
        XCTAssertEqual(allNodes.filter(\.hasAllocatedChartMetadata).count, 0)
    }
}
