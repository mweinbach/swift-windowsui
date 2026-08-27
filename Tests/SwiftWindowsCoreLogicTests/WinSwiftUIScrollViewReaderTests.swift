import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private func makeScrollReaderRuntime<V: View>(
    _ view: V,
    size: Size = Size(width: 120, height: 100),
    renderScene: Bool = true
) -> (runtime: RetainedViewRuntime, node: ViewNode) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    node.frame = Rect(origin: .zero, size: size)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    if renderScene {
        _ = runtime.renderScene()
    }
    return (runtime, node)
}

@MainActor
private func retainedScrollNodes(in root: ViewNode) -> [ViewNode] {
    var nodes: [ViewNode] = []
    var pendingNodes = [root]
    while let node = pendingNodes.popLast() {
        if node.scrollAxis != nil {
            nodes.append(node)
        }
        pendingNodes.append(contentsOf: node.children.reversed())
    }
    return nodes
}

@MainActor
private func retainedScrollTarget(named identifier: String, in root: ViewNode) -> ViewNode? {
    var pendingNodes = [root]
    while let node = pendingNodes.popLast() {
        if node.nodeTag == identifier {
            return node
        }
        pendingNodes.append(contentsOf: node.children.reversed())
    }
    return nil
}

final class WinSwiftUIScrollViewReaderTests: XCTestCase {
    func testScrollToMovesVerticalContainerOnlyEnoughToRevealItsTarget() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        Text("ZERO").frame(height: 40).id("zero")
                        Text("ONE").frame(height: 40).id("one")
                        Text("TWO").frame(height: 40).id("two")
                        Text("THREE").frame(height: 40).id("three")
                        Text("FOUR").frame(height: 40).id("four")
                        Text("FIVE").frame(height: 40).id("five")
                    }
                }
            )
            defer { withExtendedLifetime(runtime) {} }

            XCTAssertEqual(node.scrollAxis, .vertical)
            XCTAssertEqual(node.scrollOffset, 0)

            proxy?.scrollTo("three")
            XCTAssertEqual(node.scrollOffset, 60)

            proxy?.scrollTo("two")
            XCTAssertEqual(node.scrollOffset, 60, "An already-visible target must not jump")

            proxy?.scrollTo("zero")
            XCTAssertEqual(node.scrollOffset, 0)
        }
    }

    func testVerticalAnchorsAlignAndClampToContentBounds() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        Text("ZERO").frame(height: 40).id("zero")
                        Text("ONE").frame(height: 40).id("one")
                        Text("TWO").frame(height: 40).id("two")
                        Text("THREE").frame(height: 40).id("three")
                        Text("FOUR").frame(height: 40).id("four")
                        Text("FIVE").frame(height: 40).id("five")
                    }
                }
            )
            defer { withExtendedLifetime(runtime) {} }

            proxy?.scrollTo("three", anchor: .top)
            XCTAssertEqual(node.scrollOffset, 120)

            proxy?.scrollTo("three", anchor: .center)
            XCTAssertEqual(node.scrollOffset, 90)

            proxy?.scrollTo("three", anchor: .bottom)
            XCTAssertEqual(node.scrollOffset, 60)

            proxy?.scrollTo("five", anchor: .top)
            XCTAssertEqual(node.scrollOffset, 140, "The final target cannot scroll past the content")

            proxy?.scrollTo("zero", anchor: .bottom)
            XCTAssertEqual(node.scrollOffset, 0, "Leading-edge alignment must clamp at zero")
        }
    }

    func testHorizontalAnchorsUseHorizontalGeometry() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView(.horizontal) {
                        Text("ZERO").frame(width: 50).id("zero")
                        Text("ONE").frame(width: 50).id("one")
                        Text("TWO").frame(width: 50).id("two")
                        Text("THREE").frame(width: 50).id("three")
                        Text("FOUR").frame(width: 50).id("four")
                        Text("FIVE").frame(width: 50).id("five")
                    }
                }
            )
            defer { withExtendedLifetime(runtime) {} }

            XCTAssertEqual(node.scrollAxis, .horizontal)

            proxy?.scrollTo("three", anchor: .leading)
            XCTAssertEqual(node.scrollOffset, 150)

            proxy?.scrollTo("three", anchor: .center)
            XCTAssertEqual(node.scrollOffset, 115)

            proxy?.scrollTo("three", anchor: .trailing)
            XCTAssertEqual(node.scrollOffset, 80)

            proxy?.scrollTo("five", anchor: .leading)
            XCTAssertEqual(node.scrollOffset, 180)
        }
    }

    func testPreLayoutRequestsReplayInOrderDuringFirstSceneRender() async {
        await MainActor.run {
            let reader = ScrollViewReader { proxy in
                proxy.scrollTo("five", anchor: .top)
                proxy.scrollTo("three", anchor: .center)

                ScrollView {
                    Text("ZERO").frame(height: 40).id("zero")
                    Text("ONE").frame(height: 40).id("one")
                    Text("TWO").frame(height: 40).id("two")
                    Text("THREE").frame(height: 40).id("three")
                    Text("FOUR").frame(height: 40).id("four")
                    Text("FIVE").frame(height: 40).id("five")
                }
            }
            let (runtime, node) = makeScrollReaderRuntime(reader, renderScene: false)

            XCTAssertEqual(node.scrollOffset, 0)
            XCTAssertEqual(
                node.scrollProxyRequests,
                [
                    "idType:String,id:five,anchor:0.5,0.0",
                    "idType:String,id:three,anchor:0.5,0.5",
                ]
            )

            _ = runtime.renderScene()

            XCTAssertEqual(node.scrollOffset, 90)
        }
    }

    func testScrollRequestDuringLaterLayoutReplaysAfterThatPass() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        Text("ZERO").frame(height: 40).id("zero")
                        Text("ONE").frame(height: 40).id("one")
                        Text("TWO").frame(height: 40).id("two")
                        Text("THREE").frame(height: 40).id("three")
                        Text("FOUR").frame(height: 40).id("four")
                        Text("FIVE").frame(height: 40).id("five")
                    }
                }
            )

            var didRequestScroll = false
            let existingOnLayout = node.onLayout
            node.onLayout = { bounds in
                existingOnLayout?(bounds)
                guard !didRequestScroll else {
                    return
                }
                didRequestScroll = true
                proxy?.scrollTo("five", anchor: .bottom)
            }
            // Replaying the same frame is a no-op; change the width to drive
            // the later layout pass while preserving the scroll viewport height.
            node.frame.size.width += 1

            _ = runtime.renderScene()

            XCTAssertTrue(didRequestScroll)
            XCTAssertEqual(node.scrollOffset, 140)
        }
    }

    func testReconciledNewTargetScrollsAfterPendingLayoutBeforeNextRender() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let runtime = RetainedViewRuntime(root: ViewNode())
            let size = Size(width: 120, height: 100)
            runtime.setRootSize(IntSize(width: 120, height: 100))
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})

            let initialReader = ScrollViewReader { readerProxy in
                proxy = readerProxy
                ScrollView {
                    Text("ZERO").frame(height: 40).id("zero")
                    Text("ONE").frame(height: 40).id("one")
                    Text("TWO").frame(height: 40).id("two")
                    Text("THREE").frame(height: 40).id("three")
                }
            }
            host.setContent(initialReader.makeComponent(context: context))
            _ = runtime.renderScene()

            let updatedReader = ScrollViewReader { readerProxy in
                proxy = readerProxy
                ScrollView {
                    Text("ZERO").frame(height: 40).id("zero")
                    Text("ONE").frame(height: 40).id("one")
                    Text("TWO").frame(height: 40).id("two")
                    Text("THREE").frame(height: 40).id("three")
                    Text("FOUR").frame(height: 40).id("four")
                    Text("FIVE").frame(height: 40).id("five")
                }
            }
            host.setContent(updatedReader.makeComponent(context: context))

            XCTAssertTrue(runtime.hasPendingLayout)
            proxy?.scrollTo("five", anchor: .bottom)
            XCTAssertEqual(runtime.root.children.first?.scrollOffset, 0)

            _ = runtime.renderScene()

            XCTAssertEqual(runtime.root.children.first?.scrollOffset, 140)
        }
    }

    func testReorderedExistingTargetUsesItsNextLayoutPosition() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        Text("ZERO").frame(height: 40).id("zero")
                        Text("ONE").frame(height: 40).id("one")
                        Text("TWO").frame(height: 40).id("two")
                        Text("THREE").frame(height: 40).id("three")
                        Text("FOUR").frame(height: 40).id("four")
                    }
                }
            )
            guard let movedTarget = retainedScrollTarget(named: "zero", in: node) else {
                return XCTFail("Expected the existing leading row")
            }
            node.removeChild(movedTarget)
            node.addChild(movedTarget)

            XCTAssertTrue(runtime.hasPendingLayout)
            proxy?.scrollTo("zero", anchor: .top)
            XCTAssertEqual(node.scrollOffset, 0)

            _ = runtime.renderScene()

            XCTAssertEqual(node.scrollOffset, 100)
        }
    }

    func testResizedViewportUsesItsNextLayoutBounds() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        Text("ZERO").frame(height: 40).id("zero")
                        Text("ONE").frame(height: 40).id("one")
                        Text("TWO").frame(height: 40).id("two")
                        Text("THREE").frame(height: 40).id("three")
                        Text("FOUR").frame(height: 40).id("four")
                        Text("FIVE").frame(height: 40).id("five")
                    }
                }
            )
            node.frame = Rect(origin: .zero, size: Size(width: 120, height: 60))

            XCTAssertTrue(runtime.hasPendingLayout)
            proxy?.scrollTo("five", anchor: .bottom)
            XCTAssertEqual(node.scrollOffset, 0)

            _ = runtime.renderScene()

            XCTAssertEqual(node.scrollOffset, 180)
        }
    }

    func testForEachImplicitIdentitiesAreValidScrollTargets() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        ForEach(0..<12, id: \.self) { index in
                            Text("ROW \(index)").frame(height: 25)
                        }
                    }
                }
            )
            defer { withExtendedLifetime(runtime) {} }

            proxy?.scrollTo(8, anchor: .top)

            XCTAssertEqual(node.scrollOffset, 200)
            XCTAssertNotNil(retainedScrollTarget(named: "8#0", in: node))
        }
    }

    func testExplicitRowIdentityInsideForEachRemainsAddressableAlongsideImplicitIdentity() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        ForEach(0..<12, id: \.self) { index in
                            Text("ROW \(index)").frame(height: 25).id("custom-\(index)")
                        }
                    }
                }
            )
            defer { withExtendedLifetime(runtime) {} }

            proxy?.scrollTo("custom-8", anchor: .top)
            XCTAssertEqual(node.scrollOffset, 200)

            proxy?.scrollTo("custom-0", anchor: .top)
            XCTAssertEqual(node.scrollOffset, 0)

            proxy?.scrollTo(8, anchor: .top)
            XCTAssertEqual(node.scrollOffset, 200)
        }
    }

    func testExplicitRowIdentityInsideListRemainsAddressableAlongsideImplicitIdentity() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    List(0..<16, id: \.self) { index in
                        Text("ROW \(index)").frame(height: 25).id("custom-\(index)")
                    }
                }
            )
            defer { withExtendedLifetime(runtime) {} }

            proxy?.scrollTo("custom-8", anchor: .top)
            let explicitOffset = node.scrollOffset
            XCTAssertGreaterThan(explicitOffset, 0)

            proxy?.scrollTo(0, anchor: .top)
            XCTAssertLessThan(node.scrollOffset, explicitOffset)

            proxy?.scrollTo(8, anchor: .top)
            XCTAssertEqual(node.scrollOffset, explicitOffset)
        }
    }

    func testExplicitSuffixIdentityDoesNotCollideWithImplicitForEachIdentity() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        Text("EXPLICIT SUFFIX").frame(height: 40).id("8#0")
                        ForEach(0..<12, id: \.self) { index in
                            Text("ROW \(index)").frame(height: 40)
                        }
                    }
                }
            )
            defer { withExtendedLifetime(runtime) {} }

            proxy?.scrollTo(8, anchor: .top)
            XCTAssertEqual(node.scrollOffset, 360)

            proxy?.scrollTo("8#0", anchor: .top)
            XCTAssertEqual(node.scrollOffset, 0)
        }
    }

    func testInternalNodeTagsCannotSpoofExplicitScrollIdentities() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        Text("CHROME").frame(height: 40)
                        Text("ONE").frame(height: 40).id("one")
                        Text("TWO").frame(height: 40).id("two")
                        Text("EXPLICIT RESERVED ID").frame(height: 40).id("tab-indicator")
                        Text("FOUR").frame(height: 40).id("four")
                    }
                }
            )
            guard let chromeNode = node.children.first else {
                return XCTFail("Expected a retained untagged row")
            }
            chromeNode.nodeTag = "tab-indicator"

            proxy?.scrollTo("tab-indicator")
            XCTAssertEqual(node.scrollOffset, 60)

            _ = runtime.renderScene()
            chromeNode.nodeTag = "alert-scrim"

            proxy?.scrollTo("alert-scrim")

            XCTAssertEqual(node.scrollOffset, 60)
            XCTAssertFalse(runtime.isDirty)
        }
    }

    func testOffscreenLazyStackTargetScrollsIntoViewAndBecomesRealized() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    proxy = readerProxy
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<200, id: \.self) { index in
                                Text("ROW \(index)").frame(width: 120, height: 20)
                            }
                        }
                    }
                }
            )

            guard let target = retainedScrollTarget(named: "150#0", in: node) else {
                return XCTFail("Expected the offscreen ForEach row to retain its identity")
            }

            XCTAssertTrue(target.isLayoutDeferredByVirtualization)

            proxy?.scrollTo(150, anchor: .top)

            XCTAssertEqual(node.scrollOffset, 3_000)

            _ = runtime.renderScene()

            XCTAssertFalse(target.isLayoutDeferredByVirtualization)
        }
    }

    func testPreLayoutLazyStackTargetResolvesDuringFirstSceneRender() async {
        await MainActor.run {
            let reader = ScrollViewReader { proxy in
                proxy.scrollTo(180, anchor: .top)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<200, id: \.self) { index in
                            Text("ROW \(index)").frame(width: 120, height: 20)
                        }
                    }
                }
            }
            let (runtime, node) = makeScrollReaderRuntime(reader, renderScene: false)

            _ = runtime.renderScene()

            XCTAssertEqual(node.scrollOffset, 3_600)
            XCTAssertEqual(retainedScrollTarget(named: "180#0", in: node)?.isLayoutDeferredByVirtualization, false)
        }
    }

    func testNestedReadersCannotResolveTargetsOutsideTheirOwnScope() async {
        await MainActor.run {
            var outerProxy: ScrollViewProxy?
            var innerProxy: ScrollViewProxy?
            let (runtime, node) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    outerProxy = readerProxy

                    VStack(spacing: 0) {
                        ScrollView {
                            Text("OUTER ZERO").frame(height: 40).id("outer-zero")
                            Text("OUTER ONE").frame(height: 40).id("outer-one")
                            Text("OUTER TWO").frame(height: 40).id("outer-two")
                            Text("OUTER SHARED").frame(height: 40).id("shared")
                            Text("OUTER FOUR").frame(height: 40).id("outer-four")
                        }
                        .frame(height: 100)

                        ScrollViewReader { nestedProxy in
                            innerProxy = nestedProxy

                            ScrollView {
                                Text("INNER ZERO").frame(height: 40).id("inner-zero")
                                Text("INNER ONE").frame(height: 40).id("inner-one")
                                Text("INNER TWO").frame(height: 40).id("inner-two")
                                Text("INNER ONLY").frame(height: 40).id("inner-only")
                                Text("INNER SHARED").frame(height: 40).id("shared")
                            }
                            .frame(height: 100)
                        }
                    }
                },
                size: Size(width: 120, height: 200)
            )
            defer { withExtendedLifetime(runtime) {} }
            let scrollNodes = retainedScrollNodes(in: node)
            guard scrollNodes.count == 2 else {
                return XCTFail("Expected separate outer and nested-reader scroll containers")
            }

            outerProxy?.scrollTo("inner-only")
            XCTAssertEqual(scrollNodes[0].scrollOffset, 0)
            XCTAssertEqual(scrollNodes[1].scrollOffset, 0)

            outerProxy?.scrollTo("shared")
            XCTAssertEqual(scrollNodes[0].scrollOffset, 60)
            XCTAssertEqual(scrollNodes[1].scrollOffset, 0)

            innerProxy?.scrollTo("shared")
            XCTAssertEqual(scrollNodes[0].scrollOffset, 60)
            XCTAssertEqual(scrollNodes[1].scrollOffset, 100)
        }
    }

    func testMissingTargetAndDisabledScrollContainerRemainUnchanged() async {
        await MainActor.run {
            var missingTargetProxy: ScrollViewProxy?
            let (runtime, enabledNode) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    missingTargetProxy = readerProxy
                    ScrollView {
                        Text("ONE").frame(height: 80).id("one")
                        Text("TWO").frame(height: 80).id("two")
                    }
                }
            )

            missingTargetProxy?.scrollTo("missing")
            XCTAssertEqual(enabledNode.scrollOffset, 0)
            XCTAssertFalse(runtime.isDirty, "A missing target must not schedule repeated layout passes")

            _ = runtime.renderScene()

            var disabledProxy: ScrollViewProxy?
            let (disabledRuntime, disabledNode) = makeScrollReaderRuntime(
                ScrollViewReader { readerProxy in
                    disabledProxy = readerProxy
                    ScrollView {
                        Text("ONE").frame(height: 80).id("one")
                        Text("TWO").frame(height: 80).id("two")
                    }
                    .scrollDisabled()
                }
            )
            defer { withExtendedLifetime(disabledRuntime) {} }

            disabledProxy?.scrollTo("two", anchor: .bottom)

            XCTAssertNil(disabledNode.scrollAxis)
            XCTAssertEqual(disabledNode.scrollOffset, 0)
            XCTAssertFalse(disabledRuntime.isDirty, "A disabled container must not schedule repeated layout passes")
        }
    }

    func testProxyRediscoversReaderAfterComponentHostReconciliation() async {
        await MainActor.run {
            var firstProxy: ScrollViewProxy?
            var secondProxy: ScrollViewProxy?
            let runtime = RetainedViewRuntime(root: ViewNode())
            let size = Size(width: 120, height: 100)
            runtime.setRootSize(IntSize(width: 120, height: 100))
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})

            let firstReader = ScrollViewReader { proxy in
                firstProxy = proxy
                ScrollView {
                    Text("ZERO").frame(height: 40).id("zero")
                    Text("ONE").frame(height: 40).id("one")
                    Text("TWO").frame(height: 40).id("two")
                    Text("THREE").frame(height: 40).id("three")
                }
            }
            host.setContent(firstReader.makeComponent(context: context))
            _ = runtime.renderScene()

            firstProxy?.scrollTo("two")
            XCTAssertEqual(runtime.root.children.first?.scrollOffset, 20)

            let secondReader = ScrollViewReader { proxy in
                secondProxy = proxy
                ScrollView {
                    Text("ZERO").frame(height: 40).id("zero")
                    Text("ONE").frame(height: 40).id("one")
                    Text("TWO").frame(height: 40).id("two")
                    Text("THREE").frame(height: 40).id("three")
                    Text("FOUR").frame(height: 40).id("four")
                }
            }
            host.setContent(secondReader.makeComponent(context: context))
            _ = runtime.renderScene()

            secondProxy?.scrollTo("four", anchor: .bottom)

            XCTAssertEqual(runtime.root.children.first?.scrollOffset, 100)

            _ = runtime.renderScene()
            let rebuildCount = runtime.sceneRebuildCount
            XCTAssertFalse(runtime.isDirty)

            firstProxy?.scrollTo("zero", anchor: .top)

            XCTAssertEqual(runtime.root.children.first?.scrollOffset, 100)
            XCTAssertFalse(runtime.isDirty, "An obsolete proxy must not dirty or requeue its replacement")

            _ = runtime.renderScene()
            XCTAssertEqual(runtime.sceneRebuildCount, rebuildCount)
        }
    }

    func testReaderMountedInMultipleRuntimesFailsClosed() async {
        await MainActor.run {
            var proxy: ScrollViewProxy?
            let reader = ScrollViewReader { readerProxy in
                proxy = readerProxy
                ScrollView {
                    Text("ZERO").frame(height: 40).id("zero")
                    Text("ONE").frame(height: 40).id("one")
                    Text("TWO").frame(height: 40).id("two")
                    Text("THREE").frame(height: 40).id("three")
                }
            }
            let (firstRuntime, firstNode) = makeScrollReaderRuntime(reader)
            let (secondRuntime, secondNode) = makeScrollReaderRuntime(reader)

            proxy?.scrollTo("three", anchor: .bottom)

            XCTAssertEqual(firstNode.scrollOffset, 0)
            XCTAssertEqual(secondNode.scrollOffset, 0)
            XCTAssertFalse(firstRuntime.isDirty)
            XCTAssertFalse(secondRuntime.isDirty)
        }
    }
}
