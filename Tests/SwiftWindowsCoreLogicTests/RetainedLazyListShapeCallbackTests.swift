import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Checked adoption and actual lazy traversal of the live layout receiver.
/// These fixtures do not enable public List construction or qualify native
/// Arc pixels, arbitrary row factories, or State/task installation.
@MainActor
final class RetainedLazyListShapeCallbackTests: XCTestCase {
    func testCheckedAdoptionCopiesReplacesAndClearsLiveLayoutCallback() async throws {
        let retained = shapeCallbackRow("row", text: "retained")
        let first = shapeCallbackRow("row", text: "first")
        var events: [String] = []
        var receivers: [ObjectIdentifier] = []
        first.onLayout = { _ in events.append("legacy") }
        first.onLayoutWithNode = { receiver, bounds in
            XCTAssertTrue(receiver === retained)
            XCTAssertFalse(receiver === first)
            XCTAssertEqual(bounds, receiver.resolvedFrame)
            receivers.append(ObjectIdentifier(receiver))
            events.append("A")
        }
        let fixture = try ShapeCallbackFixture(previous: [retained], incoming: [first])
        defer { fixture.finish() }
        let attachment = retained.captureLazyListAttachmentProof()

        let copied = fixture.initialBuild.reconcile()

        XCTAssertTrue(copied.completed)
        XCTAssertTrue(copied.didMutate)
        XCTAssertTrue(copied.children.first === retained)
        XCTAssertTrue(events.isEmpty, "Adoption copies the receiver without delivering layout")
        XCTAssertTrue(fixture.initialBuild.finish(copied))
        _ = fixture.runtime.renderFrame()
        assertDeliveryPairs(events, nodeEvent: "A")
        let originalBounds = retained.resolvedFrame
        XCTAssertTrue(receivers.allSatisfy { $0 == ObjectIdentifier(retained) })

        events.removeAll()
        let second = shapeCallbackRow("row", text: "second")
        second.onLayout = { _ in events.append("legacy") }
        second.onLayoutWithNode = { receiver, bounds in
            XCTAssertTrue(receiver === retained)
            XCTAssertFalse(receiver === second)
            XCTAssertEqual(bounds, originalBounds)
            receivers.append(ObjectIdentifier(receiver))
            events.append("B")
        }
        let secondBuild = try fixture.prepareNext(incoming: [second])
        let replaced = secondBuild.reconcile()

        XCTAssertTrue(replaced.completed)
        XCTAssertTrue(replaced.children.first === retained)
        XCTAssertTrue(fixture.runtime.hasPendingLayout)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(secondBuild.finish(replaced))
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(retained.resolvedFrame, originalBounds)
        assertDeliveryPairs(events, nodeEvent: "B")

        events.removeAll()
        let third = shapeCallbackRow("row", text: "third")
        var installedDuringLegacy = false
        third.onLayout = { _ in
            events.append("legacy")
            if !installedDuringLegacy {
                installedDuringLegacy = true
                retained.onLayoutWithNode = { receiver, bounds in
                    XCTAssertTrue(receiver === retained)
                    XCTAssertEqual(bounds, originalBounds)
                    receivers.append(ObjectIdentifier(receiver))
                    events.append("late replacement")
                }
            }
        }
        third.onLayoutWithNode = { _, _ in events.append("obsolete snapshot") }
        let thirdBuild = try fixture.prepareNext(incoming: [third])
        let refreshed = thirdBuild.reconcile()

        XCTAssertTrue(refreshed.completed)
        XCTAssertTrue(thirdBuild.finish(refreshed))
        _ = fixture.runtime.renderFrame()
        XCTAssertTrue(installedDuringLegacy)
        XCTAssertEqual(retained.resolvedFrame, originalBounds)
        assertDeliveryPairs(events, nodeEvent: "late replacement")

        events.removeAll()
        let deliveriesBeforeClear = receivers.count
        let clearedSource = shapeCallbackRow("row", text: "cleared")
        clearedSource.onLayout = { _ in events.append("legacy") }
        let clearBuild = try fixture.prepareNext(incoming: [clearedSource])
        let cleared = clearBuild.reconcile()

        XCTAssertTrue(cleared.completed)
        XCTAssertTrue(cleared.didMutate)
        XCTAssertTrue(cleared.children.first === retained)
        XCTAssertNil(retained.onLayoutWithNode)
        XCTAssertTrue(clearBuild.finish(cleared))
        _ = fixture.runtime.renderFrame()
        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { $0 == "legacy" })
        XCTAssertEqual(receivers.count, deliveriesBeforeClear)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertTrue(retained.parent === fixture.container)
    }

    func testOutgoingLayoutCallbackCleanupKeepsReentrantReplacementAndStopsAdoption() async throws {
        let tree = ShapeCallbackReentryTree()
        let fixture = try ShapeCallbackFixture(previous: tree.previous, incoming: tree.incoming)
        defer { fixture.finish() }
        let released = ShapeCallbackReleaseObserver()
        var events: [String] = []
        var cleanups = 0
        tree.source.onLayoutWithNode = { receiver, _ in
            XCTAssertTrue(receiver === tree.retained)
            events.append("B")
        }
        installNodeCallback(
            on: tree.retained, observedBy: released, invoke: { _, _ in events.append("A") },
            onRelease: {
                cleanups += 1
                events.append("release A")
                tree.retained.onLayoutWithNode?(tree.retained, tree.retained.resolvedFrame)
                tree.retained.onLayoutWithNode = { receiver, _ in
                    XCTAssertTrue(receiver === tree.retained)
                    events.append("C")
                }
                fixture.provider.close()
            })
        XCTAssertNotNil(released.payload)
        XCTAssertTrue(fixture.initialBuild.admission.isCurrent)

        let result = fixture.initialBuild.reconcile()

        XCTAssertEqual(cleanups, 1)
        XCTAssertNil(released.payload)
        XCTAssertEqual(events, ["release A", "B"], "B must be published before A releases its capture")
        tree.assertStopped(result, in: fixture)
        tree.retained.onLayoutWithNode?(tree.retained, tree.retained.resolvedFrame)
        XCTAssertEqual(events, ["release A", "B", "C"])
        XCTAssertEqual(cleanups, 1)
        XCTAssertFalse(fixture.initialBuild.finish(result))
    }

    func testClearingLayoutCallbackRevalidatesAfterOutgoingCleanup() async throws {
        let tree = ShapeCallbackReentryTree()
        let fixture = try ShapeCallbackFixture(previous: tree.previous, incoming: tree.incoming)
        defer { fixture.finish() }
        let released = ShapeCallbackReleaseObserver()
        var cleanups = 0
        var sawPublishedNil = false
        var replacementCalls = 0
        installNodeCallback(
            on: tree.retained, observedBy: released,
            invoke: { _, _ in
                XCTFail("The outgoing layout callback is not a retirement callback")
            },
            onRelease: {
                cleanups += 1
                sawPublishedNil = tree.retained.onLayoutWithNode == nil
                tree.retained.onLayoutWithNode = { receiver, _ in
                    XCTAssertTrue(receiver === tree.retained)
                    replacementCalls += 1
                }
                fixture.provider.close()
            })
        XCTAssertNil(tree.source.onLayoutWithNode)
        XCTAssertNotNil(released.payload)
        XCTAssertTrue(fixture.initialBuild.admission.isCurrent)

        let result = fixture.initialBuild.reconcile()

        XCTAssertEqual(cleanups, 1)
        XCTAssertTrue(sawPublishedNil)
        XCTAssertNil(released.payload)
        XCTAssertNotNil(tree.retained.onLayoutWithNode)
        tree.assertStopped(result, in: fixture)
        tree.retained.onLayoutWithNode?(tree.retained, tree.retained.resolvedFrame)
        XCTAssertEqual(replacementCalls, 1)
        XCTAssertEqual(cleanups, 1)
        XCTAssertFalse(fixture.initialBuild.finish(result))
    }

    func testLegacyLayoutCleanupStopsBeforeCopyingNodeLayoutCallback() async throws {
        let tree = ShapeCallbackReentryTree()
        let fixture = try ShapeCallbackFixture(previous: tree.previous, incoming: tree.incoming)
        defer { fixture.finish() }
        let released = ShapeCallbackReleaseObserver()
        var cleanups = 0
        var publishedLegacyCalls = 0
        var oldNodeCalls = 0
        var incomingNodeCalls = 0
        tree.source.onLayout = { _ in publishedLegacyCalls += 1 }
        tree.retained.onLayoutWithNode = { receiver, _ in
            XCTAssertTrue(receiver === tree.retained)
            oldNodeCalls += 1
        }
        tree.source.onLayoutWithNode = { _, _ in incomingNodeCalls += 1 }
        installLegacyCallback(on: tree.retained, observedBy: released) {
            cleanups += 1
            tree.retained.onLayout?(tree.retained.resolvedFrame)
            fixture.provider.close()
        }
        XCTAssertTrue(fixture.initialBuild.admission.isCurrent)
        XCTAssertNotNil(released.payload)

        let result = fixture.initialBuild.reconcile()

        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(publishedLegacyCalls, 1)
        XCTAssertNil(released.payload)
        XCTAssertEqual(oldNodeCalls, 0)
        XCTAssertEqual(incomingNodeCalls, 0)
        tree.assertStopped(result, in: fixture)
        tree.retained.onLayoutWithNode?(tree.retained, tree.retained.resolvedFrame)
        XCTAssertEqual(oldNodeCalls, 1)
        XCTAssertEqual(incomingNodeCalls, 0)
        XCTAssertFalse(fixture.initialBuild.finish(result))
    }

    func testLegacyLayoutDetachmentSkipsNodeCallbackDuringLazyTraversal() async throws {
        let receiver = shapeCallbackRow("row")
        let fixture = try ShapeCallbackFixture(previous: [], incoming: [receiver])
        defer { fixture.finish() }
        let installed = fixture.initialBuild.reconcile()
        XCTAssertTrue(installed.completed)
        XCTAssertTrue(fixture.initialBuild.finish(installed))
        _ = fixture.runtime.renderFrame()
        try assertInitialLayout(fixture, receiver: receiver)
        let attachment = receiver.captureLazyListAttachmentProof()
        let detachedParent = ViewNode()
        var legacyCalls = 0
        var nodeCalls = 0
        var detachedBeforeProviderClose = false
        receiver.onLayoutWithNode = { _, _ in nodeCalls += 1 }
        receiver.onLayout = { _ in
            legacyCalls += 1
            XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.container))
            XCTAssertTrue(fixture.runtime.permitsRetainedActionInvocation)
            XCTAssertFalse(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 16, roundLimit: 4))
            receiver.removeFromParent()
            detachedParent.addChild(receiver)
            detachedBeforeProviderClose = !attachment.isCurrent
            XCTAssertTrue(detachedBeforeProviderClose)
            XCTAssertNotNil(fixture.provider.metadata)
            // Closing only prevents another candidate from rebuilding the row.
            // Actual detach/reparent already revoked the traversal's witness.
            fixture.provider.close()
        }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(legacyCalls, 1)
        XCTAssertEqual(nodeCalls, 0)
        XCTAssertTrue(detachedBeforeProviderClose)
        XCTAssertFalse(attachment.isCurrent)
        XCTAssertTrue(receiver.parent === detachedParent)
        XCTAssertTrue(detachedParent.children.first === receiver)
        XCTAssertTrue(fixture.container.children.isEmpty)
        XCTAssertTrue(fixture.runtime.permitsRetainedActionInvocation)
        assertIncompleteLayout(fixture)
    }

    func testNodeLayoutDetachmentStopsPositioningAndDescendantLayout() async throws {
        let receiver = shapeCallbackRow("row")
        receiver.scrollAxis = .vertical
        let child = shapeCallbackRow("child")
        child.preferredSize = Size(width: 120, height: 100)
        receiver.addChild(child)
        let fixture = try ShapeCallbackFixture(previous: [], incoming: [receiver])
        defer { fixture.finish() }
        let installed = fixture.initialBuild.reconcile()
        XCTAssertTrue(installed.completed)
        XCTAssertTrue(fixture.initialBuild.finish(installed))
        _ = fixture.runtime.renderFrame()
        try assertInitialLayout(fixture, receiver: receiver)
        let attachment = receiver.captureLazyListAttachmentProof()
        let detachedParent = ViewNode()
        let callbackFrame = Rect(x: 71, y: 83, width: 13, height: 17)
        let callbackChildFrame = Rect(x: 29, y: 31, width: 37, height: 41)
        let callbackOffset = 43.0
        var nodeCalls = 0
        var childLayouts = 0
        var childPlacements = 0
        var detachedBeforeProviderClose = false
        child.onLayout = { _ in childLayouts += 1 }
        receiver.absoluteChildFrame = { _, _ in
            childPlacements += 1
            return Rect(x: 1, y: 2, width: 3, height: 4)
        }
        receiver.onLayoutWithNode = { live, _ in
            nodeCalls += 1
            XCTAssertTrue(live === receiver)
            XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.container))
            XCTAssertFalse(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 16, roundLimit: 4))
            live.removeFromParent()
            detachedParent.addChild(live)
            detachedBeforeProviderClose = !attachment.isCurrent
            XCTAssertTrue(detachedBeforeProviderClose)
            XCTAssertNotNil(fixture.provider.metadata)
            live.position = Point(x: 500, y: 600)
            live.resolvedFrame = callbackFrame
            live.resolvedScrollOffset = callbackOffset
            child.resolvedFrame = callbackChildFrame
            fixture.provider.close()
        }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(nodeCalls, 1)
        XCTAssertTrue(detachedBeforeProviderClose)
        XCTAssertFalse(attachment.isCurrent)
        XCTAssertTrue(receiver.parent === detachedParent)
        XCTAssertTrue(child.parent === receiver)
        XCTAssertEqual(receiver.position, Point(x: 500, y: 600))
        XCTAssertEqual(receiver.resolvedFrame, callbackFrame)
        XCTAssertEqual(receiver.resolvedScrollOffset, callbackOffset)
        XCTAssertEqual(child.resolvedFrame, callbackChildFrame)
        XCTAssertEqual(childPlacements, 0)
        XCTAssertEqual(childLayouts, 0)
        XCTAssertTrue(fixture.container.children.isEmpty)
        XCTAssertTrue(fixture.runtime.permitsRetainedActionInvocation)
        assertIncompleteLayout(fixture)
    }

    func testCheckedArcAdoptionUpdatesRetainedGeometryWithoutRestoringOldPaint() async throws {
        let fill = WinSwiftUI.LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let stroke = WinSwiftUI.LinearGradient(colors: [.green, .white], startPoint: .top, endPoint: .bottom)
        let strokeStyle = StrokeStyle(
            lineWidth: 3, dashPattern: [3, 2], dashOffset: 1,
            lineCap: .round, lineJoin: .bevel, miterLimit: 2)
        let oldArc = Arc(startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        let retained = makeArcNode(
            AnyShape(oldArc.fill(.green)).stroke(stroke, style: strokeStyle).fill(fill, style: FillStyle(eoFill: true)))
        let fixture = try ShapeCallbackFixture(previous: [], incoming: [retained])
        defer { fixture.finish() }
        let inserted = fixture.initialBuild.reconcile()
        XCTAssertTrue(inserted.completed)
        XCTAssertTrue(fixture.initialBuild.finish(inserted))
        let initialFrame = fixture.runtime.renderFrame()
        try assertInitialLayout(fixture, receiver: retained)
        let attachment = retained.captureLazyListAttachmentProof()
        let originalBounds = retained.resolvedFrame
        let originalPath = try XCTUnwrap(retained.backgroundPath)
        XCTAssertGreaterThan(originalPath.segments.count, 1)
        // Stored geometry is normalized for one later paint scale. The 3-point
        // border leaves a 114x34 rectangle at (3,3): center (60,20), radius 17.
        assertArcGeometry(
            originalPath, move: Point(x: 37.0 / 57, y: 0.5), center: Point(x: 0.5, y: 0.5), radius: 17.0 / 114)
        assertFrameGeometryAndPixels(
            initialFrame, size: IntSize(width: 120, height: 80), move: Point(x: 77, y: 20),
            center: Point(x: 60, y: 20), radius: 17,
            probes: [(60, 30, .red), (48, 15, .black), (72, 24, .red)])
        XCTAssertEqual(retained.backgroundColor, .red)
        XCTAssertEqual(retained.backgroundGradient, .linear(.init(fill)))
        XCTAssertEqual(retained.borderColor, .green)
        XCTAssertEqual(retained.borderGradient, .linear(.init(stroke)))
        XCTAssertEqual(retained.borderWidth, 3)
        XCTAssertEqual(retained.borderStrokeStyle, strokeStyle)
        XCTAssertEqual(retained.clipFillStyle, RetainedClipFillStyle(eoFill: true))

        let newArc = Arc(startAngle: .degrees(35), endAngle: .degrees(215), clockwise: false)
        // The inner Arc deliberately disagrees with the complete outer paint.
        // Its live geometry callback must not restore this green stroke/fill.
        let incoming = makeArcNode(AnyShape(newArc.stroke(.green, lineWidth: 9).fill(.green)).fill(.blue))
        XCTAssertNil(incoming.backgroundPath)
        let build = try fixture.prepareNext(incoming: [incoming])
        let adopted = build.reconcile()

        XCTAssertTrue(adopted.completed)
        XCTAssertTrue(adopted.didMutate)
        XCTAssertTrue(adopted.children.first === retained)
        XCTAssertFalse(incoming === retained)
        XCTAssertTrue(fixture.runtime.hasPendingLayout)
        assertResetArcPaint(retained)
        XCTAssertTrue(build.finish(adopted))
        let adoptedFrame = fixture.runtime.renderFrame()
        XCTAssertEqual(retained.resolvedFrame, originalBounds)
        let updatedPath = try XCTUnwrap(retained.backgroundPath)
        // Independent trigonometric constants for 35 degrees. Outer paint has
        // removed the border, so the 120x40 circle has center (60,20), radius 20.
        let cos35 = 0.8191520442889918
        let sin35 = 0.5735764363510460
        let start = 35.0 * Double.pi / 180
        let end = 215.0 * Double.pi / 180
        assertArcGeometry(
            updatedPath, move: Point(x: 0.5 + cos35 / 6, y: 0.5 + sin35 / 2),
            center: Point(x: 0.5, y: 0.5), radius: 1.0 / 6, start: start, end: end)
        assertFrameGeometryAndPixels(
            adoptedFrame, size: IntSize(width: 120, height: 80),
            move: Point(x: 60 + 20 * cos35, y: 20 + 20 * sin35),
            center: Point(x: 60, y: 20), radius: 20, start: start, end: end,
            probes: [(48, 15, .blue), (72, 24, .black)])
        XCTAssertNotEqual(updatedPath, originalPath)
        XCTAssertNil(incoming.backgroundPath, "Layout must target the retained receiver, not the discarded source")
        assertResetArcPaint(retained)

        fixture.runtime.setRootSize(IntSize(width: 160, height: 80))
        let resizedFrame = fixture.runtime.renderFrame()
        XCTAssertTrue(fixture.container.children.first === retained)
        XCTAssertEqual(retained.resolvedFrame.size, Size(width: 160, height: 40))
        let resizedPath = try XCTUnwrap(retained.backgroundPath)
        // A 160x40 rectangle moves the center to (80,20), keeping radius 20.
        assertArcGeometry(
            resizedPath, move: Point(x: 0.5 + cos35 / 8, y: 0.5 + sin35 / 2),
            center: Point(x: 0.5, y: 0.5), radius: 1.0 / 8, start: start, end: end)
        assertFrameGeometryAndPixels(
            resizedFrame, size: IntSize(width: 160, height: 80),
            move: Point(x: 80 + 20 * cos35, y: 20 + 20 * sin35),
            center: Point(x: 80, y: 20), radius: 20, start: start, end: end,
            probes: [(68, 15, .blue), (92, 24, .black), (48, 15, .black)])
        XCTAssertNotEqual(resizedPath, updatedPath)
        XCTAssertNil(incoming.backgroundPath)
        XCTAssertTrue(attachment.isCurrent)
        assertResetArcPaint(retained)

        func assertArcGeometry(
            _ path: RenderPath, move: Point, center: Point, radius: Double,
            start: Double = 0, end: Double = .pi, file: StaticString = #filePath, line: UInt = #line
        ) {
            XCTAssertEqual(path.segments.count, 2, "One move and one open arc", file: file, line: line)
            guard path.segments.count == 2, case .moveTo(let actualMove) = path.segments[0],
                case .arc(let actualCenter, let actualRadius, let actualStart, let actualEnd, let clockwise) =
                    path.segments[1]
            else {
                XCTFail("Expected one move followed by an open arc", file: file, line: line)
                return
            }
            XCTAssertTrue(
                [actualMove.x, actualMove.y, actualCenter.x, actualCenter.y, actualRadius, actualStart, actualEnd]
                    .allSatisfy(\.isFinite), file: file, line: line)
            XCTAssertEqual(actualMove.x, move.x, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(actualMove.y, move.y, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(actualCenter.x, center.x, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(actualCenter.y, center.y, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(actualRadius, radius, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(actualStart, start, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(actualEnd, end, accuracy: 1e-9, file: file, line: line)
            XCTAssertFalse(clockwise, file: file, line: line)
        }

        func assertFrameGeometryAndPixels(
            _ frame: RenderFrame, size: IntSize, move: Point, center: Point, radius: Double,
            start: Double = 0, end: Double = .pi, probes: [(Int, Int, Color)],
            file: StaticString = #filePath, line: UInt = #line
        ) {
            let fills = frame.commands.compactMap { command -> FillPathCommand? in
                guard case .fillPath(let fill) = command else { return nil }
                return fill
            }
            XCTAssertEqual(fills.count, 1, file: file, line: line)
            if let fill = fills.first {
                assertArcGeometry(
                    fill.path, move: move, center: center, radius: radius, start: start, end: end, file: file,
                    line: line)
            }
            XCTAssertEqual(frame.clearColor, .black, file: file, line: line)
            XCTAssertTrue(probes.contains { $0.2 != .black }, "Require positive coverage", file: file, line: line)
            let bitmap = GPUIRawSceneRasterizer.rasterize(frame, size: size)
            for (x, y, color) in probes {
                guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
                    XCTFail("Pixel probe outside the raster", file: file, line: line)
                    continue
                }
                let offset = y * Int(bitmap.bytesPerRow) + x * 4
                guard offset + 4 <= bitmap.pixels.count else {
                    XCTFail("Pixel probe outside the byte buffer", file: file, line: line)
                    continue
                }
                let expected = [color.blue, color.green, color.red, color.alpha].map { UInt8(($0 * 255).rounded()) }
                XCTAssertEqual(Array(bitmap.pixels[offset..<(offset + 4)]), expected, file: file, line: line)
            }
        }
    }

    private func assertDeliveryPairs(
        _ events: [String], nodeEvent: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard !events.isEmpty, events.count.isMultiple(of: 2) else {
            return XCTFail("Every delivered node callback needs its preceding legacy callback", file: file, line: line)
        }
        // A convergence pass may revisit a node. Every visit must still read
        // the current callback after legacy delivery, without calling an old one.
        for index in stride(from: 0, to: events.count, by: 2) {
            XCTAssertEqual(Array(events[index..<(index + 2)]), ["legacy", nodeEvent], file: file, line: line)
        }
    }

    private func assertInitialLayout(
        _ fixture: ShapeCallbackFixture, receiver: ViewNode, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertTrue(fixture.container.children.first === receiver, file: file, line: line)
        XCTAssertTrue(receiver.parent === fixture.container, file: file, line: line)
        XCTAssertTrue(fixture.adapter.ownsAttachment(fixture.container), file: file, line: line)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 1, file: file, line: line)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork, file: file, line: line)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .complete, file: file, line: line)
        guard case .settled(let receipt) = fixture.runtime.layoutSettlementStatus else {
            XCTFail("The ordinary initial lazy pass must settle before callback invalidation", file: file, line: line)
            throw ShapeCallbackFixtureError.setup
        }
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
    }

    private func assertIncompleteLayout(
        _ fixture: ShapeCallbackFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        if case .settled = fixture.runtime.layoutSettlementStatus {
            XCTFail("An attachment-invalidated callback cannot supply settlement", file: file, line: line)
        }
        XCTAssertNotEqual(fixture.runtime.lastLazyListWorkCompletion, .complete, file: file, line: line)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild, file: file, line: line)
    }

    private func makeArcNode(_ shape: AnyShape) -> ViewNode {
        let constructionRuntime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 120, height: 80) }, invalidateHandler: {})
        let node = shape.makeComponent(context: context).makeNode(runtime: constructionRuntime)
        node.nodeTag = "arc"
        node.preferredSize = Size(width: 120, height: 40)
        return node
    }

    private func assertResetArcPaint(
        _ node: ViewNode, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(node.backgroundColor, .blue, file: file, line: line)
        XCTAssertNil(node.backgroundGradient, file: file, line: line)
        XCTAssertEqual(node.borderColor, .clear, file: file, line: line)
        XCTAssertNil(node.borderGradient, file: file, line: line)
        XCTAssertEqual(node.borderWidth, 0, file: file, line: line)
        XCTAssertNil(node.borderStrokeStyle, file: file, line: line)
        XCTAssertNil(node.clipFillStyle, file: file, line: line)
    }

    private func installNodeCallback(
        on node: ViewNode, observedBy observer: ShapeCallbackReleaseObserver,
        invoke: @escaping @MainActor (ViewNode, Rect) -> Void, onRelease: @escaping @MainActor () -> Void
    ) {
        let payload = ShapeCallbackReleasePayload(onRelease)
        observer.payload = payload
        node.onLayoutWithNode = { [payload] receiver, bounds in
            withExtendedLifetime(payload) { invoke(receiver, bounds) }
        }
    }

    private func installLegacyCallback(
        on node: ViewNode, observedBy observer: ShapeCallbackReleaseObserver,
        onRelease: @escaping @MainActor () -> Void
    ) {
        let payload = ShapeCallbackReleasePayload(onRelease)
        observer.payload = payload
        node.onLayout = { [payload] _ in withExtendedLifetime(payload) {} }
    }
}

@MainActor
private func shapeCallbackRow(_ tag: String, text: String? = nil) -> ViewNode {
    let node = ViewNode(
        frame: Rect(x: 0, y: 0, width: 120, height: 20), text: text,
        preferredSize: Size(width: 120, height: 20))
    node.nodeTag = tag
    return node
}

@MainActor
private final class ShapeCallbackReentryTree {
    let retained = shapeCallbackRow("row", text: "old row")
    let source = shapeCallbackRow("row", text: "new row")
    let child = shapeCallbackRow("child", text: "old child")
    let sourceChild = shapeCallbackRow("child", text: "new child")
    let sibling = shapeCallbackRow("sibling", text: "old sibling")
    let sourceSibling = shapeCallbackRow("sibling", text: "new sibling")
    private let oldPlacement = Rect(x: 7, y: 8, width: 9, height: 10)
    private var laterPlacements = 0
    private var updates: [String] = []
    var previous: [ViewNode] { [retained, sibling] }
    var incoming: [ViewNode] { [source, sourceSibling] }

    init() {
        retained.addChild(child)
        source.addChild(sourceChild)
        retained.absoluteChildFrame = { [oldPlacement] _, _ in oldPlacement }
        source.absoluteChildFrame = { [weak self] _, _ in
            self?.laterPlacements += 1
            return Rect(x: 1, y: 2, width: 3, height: 4)
        }
        source.onUpdatePlatformView = { [weak self] _ in self?.updates.append("row") }
        sourceChild.onUpdatePlatformView = { [weak self] _ in self?.updates.append("child") }
        sourceSibling.onUpdatePlatformView = { [weak self] _ in self?.updates.append("sibling") }
    }

    func assertStopped(
        _ result: RetainedLazyListAdoptionResult, in fixture: ShapeCallbackFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(result.completed, file: file, line: line)
        XCTAssertTrue(result.didMutate, file: file, line: line)
        XCTAssertNil(result.completion, file: file, line: line)
        XCTAssertFalse(fixture.initialBuild.admission.isCurrent, file: file, line: line)
        XCTAssertNil(fixture.provider.metadata, file: file, line: line)
        XCTAssertEqual(retained.text, "new row", "Earlier property writes are not rolled back", file: file, line: line)
        XCTAssertTrue(retained.children.first === child, file: file, line: line)
        XCTAssertTrue(child.parent === retained, file: file, line: line)
        XCTAssertEqual(child.text, "old child", file: file, line: line)
        XCTAssertEqual(sibling.text, "old sibling", file: file, line: line)
        XCTAssertEqual(
            result.children.map(ObjectIdentifier.init), previous.map(ObjectIdentifier.init), file: file, line: line)
        XCTAssertNil(retained.onUpdatePlatformView, file: file, line: line)
        XCTAssertTrue(updates.isEmpty, file: file, line: line)
        XCTAssertEqual(
            retained.absoluteChildFrame?(child, retained.resolvedFrame), oldPlacement, file: file, line: line)
        XCTAssertEqual(laterPlacements, 0, file: file, line: line)
    }
}

@MainActor
private final class ShapeCallbackFixture {
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let initialBuild: ShapeCallbackBuild
    private let lease: ShapeCallbackLease
    private var builds: [ShapeCallbackBuild]
    private var fixtureRoots: [ViewNode]
    private var didFinish = false

    init(previous: [ViewNode], incoming: [ViewNode]) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        try Self.configure(provider, incoming: incoming, identityNodes: previous + incoming)
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 40, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let container = ViewNode(
            layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)), children: previous)
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 80), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
            children: [container])
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 0 }
        let lease = ShapeCallbackLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        guard adapter.ownsAttachment(container),
            runtime.configureLazyListResolutionBudget(elementLimit: 16, roundLimit: 4)
        else { throw ShapeCallbackFixtureError.setup }
        let initialBuild = try ShapeCallbackBuild(
            adapter: adapter, container: container, runtime: runtime, lease: lease)
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        self.initialBuild = initialBuild
        self.builds = [initialBuild]
        self.fixtureRoots = previous + incoming + [container, root]
    }

    func prepareNext(incoming: [ViewNode]) throws -> ShapeCallbackBuild {
        guard !didFinish, builds.allSatisfy(\.isFinished) else { throw ShapeCallbackFixtureError.setup }
        try Self.configure(provider, incoming: incoming, identityNodes: incoming)
        fixtureRoots.append(contentsOf: incoming)
        let build = try ShapeCallbackBuild(adapter: adapter, container: container, runtime: runtime, lease: lease)
        builds.append(build)
        return build
    }

    private static func configure(
        _ provider: RetainedLazyListDataSource<Int, [ViewNode]>, incoming: [ViewNode], identityNodes: [ViewNode]
    ) throws {
        guard
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]), rowContent: { _, _ in incoming })
        else { throw ShapeCallbackFixtureError.setup }
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        var configured: Set<ObjectIdentifier> = []
        for node in identityNodes where configured.insert(ObjectIdentifier(node)).inserted {
            let tag = try XCTUnwrap(node.nodeTag)
            node.retainedViewIdentity = prefix.appending(contentsOf: [.role(.content), .explicit(.init(tag))])
        }
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        runtime.stopRenderLifecycleCallbacks()
        provider.close()
        runtime.clock = { 0 }
        var pending = fixtureRoots
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            pending.append(contentsOf: node.children)
            node.onLayout = nil
            node.onLayoutWithNode = nil
            node.absoluteChildFrame = nil
            node.onUpdatePlatformView = nil
        }
        for build in builds where !build.isFinished { _ = build.finish() }
        runtime.cancelRenderLifecycleTasks()
    }
}

@MainActor
private final class ShapeCallbackBuild {
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    private let adapter: RetainedLazyListRuntimeAdapter
    private let container: ViewNode
    private let runtime: RetainedViewRuntime
    private let epoch: any RetainedBuildEpoch
    private(set) var isFinished = false

    init(
        adapter: RetainedLazyListRuntimeAdapter, container: ViewNode,
        runtime: RetainedViewRuntime, lease: ShapeCallbackLease
    ) throws {
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: runtime.root.frame.width, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: runtime.root.frame.height))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = try XCTUnwrap(lease.beginBuild())
        coordinator.install(epoch, startedAt: sequence)
        var prepared = false
        defer {
            if !prepared {
                epoch.abandon()
                epoch.finishAfterCallbacks()
                coordinator.finishBuild()
            }
        }
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime,
            coordinator: coordinator, sequence: sequence)
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission),
            admission.installCandidate(candidate), epoch.willAdopt(), admission.isCurrent
        else { throw ShapeCallbackFixtureError.setup }
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.epoch = epoch
        self.candidate = candidate
        self.admission = admission
        prepared = true
    }

    func reconcile() -> RetainedLazyListAdoptionResult {
        ComponentHost.reconcileChildren(
            of: container, oldChildren: container.children, newNodes: candidate.children, admission: admission)
    }

    @discardableResult
    func finish(_ result: RetainedLazyListAdoptionResult? = nil) -> Bool {
        guard !isFinished else { return false }
        let completed =
            result?.completed == true && admission.isCurrent
            && adapter.complete(candidate: candidate, adoptedChildren: container.children)
        isFinished = true
        if completed || admission.didMutate { epoch.commit() } else { epoch.abandon() }
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
        return completed
    }
}

private enum ShapeCallbackFixtureError: Error { case setup }

@MainActor
private final class ShapeCallbackLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { ShapeCallbackEpoch() }
}

@MainActor
private final class ShapeCallbackEpoch: RetainedBuildEpoch {
    private var prepared = false
    private var superseded = false
    var canAdopt: Bool { !prepared && !superseded }
    func supersede() { superseded = true }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}

@MainActor
private final class ShapeCallbackReleaseObserver {
    weak var payload: ShapeCallbackReleasePayload?
}

private final class ShapeCallbackReleasePayload {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    deinit { MainActor.assumeIsolated { [action] in action() } }
}
