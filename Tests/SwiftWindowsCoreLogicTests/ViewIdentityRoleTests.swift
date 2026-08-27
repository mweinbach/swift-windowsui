import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewIdentityRoleTests: XCTestCase {
    func testTableReorderKeepsTypedRowsAndSeparatesHeaderAndColumnRoles() async throws {
        var rows = [ViewIdentityRoleRow(1), ViewIdentityRoleRow(2)]
        var selection: ViewIdentityRoleKey? = rows[0].id
        let fixture = ViewIdentityRoleHost {
            Table(rows, selection: Binding<ViewIdentityRoleKey?>(get: { selection }, set: { selection = $0 })) {
                AnyTableColumn<ViewIdentityRoleRow>(
                    title: "First",
                    cellBuilder: { row in
                        viewIdentityRoleText("First \(row.id.value)", identifier: "first.\(row.id.value)")
                    },
                    headerBuilder: { viewIdentityRoleText("First", identifier: "header.first") })
                AnyTableColumn<ViewIdentityRoleRow>(
                    title: "Second",
                    cellBuilder: { row in
                        viewIdentityRoleText("Second \(row.id.value)", identifier: "second.\(row.id.value)")
                    },
                    headerBuilder: { viewIdentityRoleText("Second", identifier: "header.second") })
            }
        }
        let table = try fixture.contentRoot()
        XCTAssertEqual(table.children.count, 3)
        let header = try XCTUnwrap(table.children.first)
        let firstRow = try XCTUnwrap(table.children.dropFirst().first)
        let secondRow = try XCTUnwrap(table.children.dropFirst(2).first)
        let firstIdentity = try XCTUnwrap(firstRow.retainedViewIdentity)
        let secondIdentity = try XCTUnwrap(secondRow.retainedViewIdentity)
        XCTAssertNotEqual(firstIdentity, secondIdentity)
        XCTAssertTrue(firstIdentity.segments.contains(.role(.row)))
        XCTAssertTrue(firstIdentity.segments.contains(.keyed(.init(ViewIdentityRoleKey(value: 1)))))
        XCTAssertTrue(secondIdentity.segments.contains(.keyed(.init(ViewIdentityRoleKey(value: 2)))))
        XCTAssertTrue(try XCTUnwrap(header.retainedViewIdentity).segments.contains(.role(.header)))

        let identifiers = ["header.first", "header.second", "first.1", "second.1", "first.2", "second.2"]
        let before = try fixture.snapshots(identifiers)
        XCTAssertEqual(Set(before.values.map(\.identity)).count, identifiers.count)
        for identifier in ["header.first", "header.second"] {
            XCTAssertTrue(try XCTUnwrap(before[identifier]).identity.segments.contains(.role(.columnHeader)))
        }
        for identifier in ["first.1", "second.1", "first.2", "second.2"] {
            let identity = try XCTUnwrap(before[identifier]).identity
            XCTAssertTrue(identity.segments.contains(.role(.row)))
            XCTAssertTrue(identity.segments.contains(.role(.column)))
            XCTAssertFalse(identity.segments.contains(.role(.columnHeader)))
        }

        rows.reverse()
        fixture.reload()

        XCTAssertTrue(try fixture.contentRoot() === table)
        XCTAssertTrue(table.children.first === header)
        XCTAssertTrue(table.children.dropFirst().first === secondRow)
        XCTAssertTrue(table.children.dropFirst(2).first === firstRow)
        XCTAssertEqual(firstRow.retainedViewIdentity, firstIdentity)
        XCTAssertEqual(secondRow.retainedViewIdentity, secondIdentity)
        for (identifier, snapshot) in before {
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
    }

    func testSplitViewFilteringKeepsTheOriginalDetailRoleAndNode() async throws {
        var visibility = NavigationSplitViewVisibility.all
        let fixture = ViewIdentityRoleHost {
            NavigationSplitView(columnVisibility: Binding(get: { visibility }, set: { visibility = $0 })) {
                Text("Sidebar").accessibilityIdentifier("sidebar")
            } content: {
                Text("Content").accessibilityIdentifier("content")
            } detail: {
                Text("Detail").accessibilityIdentifier("detail")
            }
        }
        let container = try fixture.contentRoot()
        let before = try fixture.snapshots(["sidebar", "content", "detail"])
        let detail = try XCTUnwrap(before["detail"])
        XCTAssertEqual(container.children.count, 3)
        XCTAssertEqual(Set(before.values.map(\.identity)).count, 3)
        XCTAssertTrue(detail.identity.segments.contains(.role(.detail)))
        XCTAssertFalse(detail.identity.segments.contains(.role(.sidebar)))

        visibility = .detailOnly
        fixture.reload()

        XCTAssertTrue(try fixture.contentRoot() === container)
        XCTAssertEqual(container.children.count, 1)
        detail.assertRetained(as: try fixture.node("detail"))
        XCTAssertTrue(container.children.first === detail.node)
        XCTAssertFalse(fixture.nodes.contains { $0.accessibilityIdentifier == "sidebar" })
        XCTAssertFalse(fixture.nodes.contains { $0.accessibilityIdentifier == "content" })

        visibility = .all
        fixture.reload()

        XCTAssertEqual(container.children.count, 3)
        detail.assertRetained(as: try fixture.node("detail"))
        for identifier in ["sidebar", "content"] {
            let original = try XCTUnwrap(before[identifier])
            let restored = try fixture.node(identifier)
            XCTAssertEqual(restored.retainedViewIdentity, original.identity)
            XCTAssertFalse(restored === original.node, "A removed column returns as a new node at its original role")
        }
    }

    func testSceneEnvironmentsPreserveKeyedMetadataInSnapshotsAndBothFactories() async throws {
        let shared = ViewIdentityRoleEnvironmentModel()
        let originalViews = viewIdentityRoleSceneRows([1, 2])
        var configuration = WindowGroupConfiguration(
            title: "Role mapping", size: IntSize(width: 400, height: 400), clearColor: .clear,
            content: originalViews, forType: [Int].self,
            dataBoundContent: { payload in
                guard let rows = payload.base as? [Int] else { return [] }
                return viewIdentityRoleSceneRows(rows)
            })
        configuration.windowContentFactory = { viewIdentityRoleSceneRows([1, 2]) }
        let mapped = ViewIdentityRoleScene(configuration: configuration)
            .environment(\.isEnabled, false)
            .environmentObject(shared)
            .makeWindowConfiguration()
        let windowFactory = try XCTUnwrap(mapped.windowContentFactory)
        let dataFactory = try XCTUnwrap(mapped.dataBoundContent)
        let variants: [(String, [AnyView])] = [
            ("snapshot", mapped.content),
            ("window factory", windowFactory()),
            ("data factory", dataFactory(AnyHashable([1, 2]))),
        ]
        let originalMetadata = originalViews.map(\.structuralIdentity)
        XCTAssertEqual(originalMetadata.count, 2)
        XCTAssertNotEqual(originalMetadata.first, originalMetadata.last)
        for (index, key) in [1, 2].enumerated() {
            XCTAssertTrue(originalMetadata[index].contains(.keyed(.init(key))))
        }

        for (label, views) in variants {
            XCTAssertEqual(views.map(\.structuralIdentity), originalMetadata, label)
            var currentViews = views
            let fixture = ViewIdentityRoleHost(views: { currentViews })
            let before = try fixture.snapshots(["scene.1", "scene.2"])
            XCTAssertEqual(try fixture.node("scene.1").text, "Disabled shared 1", label)
            XCTAssertEqual(try fixture.node("scene.2").text, "Disabled shared 2", label)

            currentViews.reverse()
            fixture.reload()

            XCTAssertEqual(fixture.nodes.compactMap(\.text), ["Disabled shared 2", "Disabled shared 1"], label)
            for (identifier, snapshot) in before {
                snapshot.assertRetained(as: try fixture.node(identifier))
            }
        }
    }

    func testDeferredGeometryResizeKeepsReaderAndContentIdentityPaths() async throws {
        let fixture = ViewIdentityRoleHost {
            VStack(spacing: 0) {
                Color.red.frame(height: 80)
                GeometryReader { proxy in
                    Text("Slot \(Int(proxy.size.width.rounded())) \(Int(proxy.size.height.rounded()))")
                        .accessibilityIdentifier("geometry.leaf")
                }
            }
        }
        let readerNode = try XCTUnwrap(fixture.nodes.first { $0.geometryReaderBuild != nil })
        let reader = try ViewIdentityRoleSnapshot(readerNode)
        let leaf = try ViewIdentityRoleSnapshot(fixture.node("geometry.leaf"))
        let readerType = RetainedViewIdentity.Segment.view(ObjectIdentifier(GeometryReader.self))
        XCTAssertEqual(reader.identity.segments.filter { $0 == readerType }.count, 1)
        XCTAssertTrue(leaf.identity.segments.contains(.role(.geometryContent)))
        XCTAssertEqual(leaf.identity.segments.filter { $0 == readerType }.count, 1)
        XCTAssertEqual(leaf.node.text, "Slot 400 320")
        var resolveCount = fixture.runtime.geometryReaderResolveCount
        XCTAssertGreaterThan(resolveCount, 0)

        for size in [IntSize(width: 640, height: 480), IntSize(width: 360, height: 280)] {
            fixture.runtime.setRootSize(size)
            _ = fixture.runtime.renderFrame()

            reader.assertRetained(as: try XCTUnwrap(fixture.nodes.first { $0.geometryReaderBuild != nil }))
            leaf.assertRetained(as: try fixture.node("geometry.leaf"))
            XCTAssertEqual(leaf.node.text, "Slot \(size.width) \(size.height - 80)")
            XCTAssertGreaterThan(fixture.runtime.geometryReaderResolveCount, resolveCount)
            resolveCount = fixture.runtime.geometryReaderResolveCount
        }

        fixture.reload()

        reader.assertRetained(as: try XCTUnwrap(fixture.nodes.first { $0.geometryReaderBuild != nil }))
        leaf.assertRetained(as: try fixture.node("geometry.leaf"))
        XCTAssertEqual(leaf.node.text, "Slot 360 200")
    }
}

private struct ViewIdentityRoleKey: Hashable, CustomStringConvertible {
    let value: Int

    var description: String { "same" }
}

private struct ViewIdentityRoleRow: Identifiable {
    let id: ViewIdentityRoleKey

    init(_ value: Int) {
        id = ViewIdentityRoleKey(value: value)
    }
}

@MainActor
private final class ViewIdentityRoleEnvironmentModel: ObservableObject {
    @Published var label = "shared"
}

private struct ViewIdentityRoleEnvironmentProbe: View {
    let row: Int
    @Environment(\.isEnabled) private var isEnabled
    @EnvironmentObject private var shared: ViewIdentityRoleEnvironmentModel

    var body: some View {
        Text("\(isEnabled ? "Enabled" : "Disabled") \(shared.label) \(row)")
            .accessibilityIdentifier("scene.\(row)")
    }
}

private struct ViewIdentityRoleScene: Scene {
    typealias Body = Never

    let configuration: WindowGroupConfiguration

    var body: Never { fatalError("ViewIdentityRoleScene has no body") }

    func makeWindowConfiguration() -> WindowGroupConfiguration { configuration }
}

@MainActor
@ViewBuilder
private func viewIdentityRoleText(_ text: String, identifier: String) -> [AnyView] {
    Text(text).accessibilityIdentifier(identifier)
}

@MainActor
@ViewBuilder
private func viewIdentityRoleSceneRows(_ rows: [Int]) -> [AnyView] {
    ForEach(rows, id: \.self) { row in
        ViewIdentityRoleEnvironmentProbe(row: row)
    }
}

@MainActor
private struct ViewIdentityRoleSnapshot {
    let node: ViewNode
    let identity: RetainedViewIdentity

    init(_ node: ViewNode, file: StaticString = #filePath, line: UInt = #line) throws {
        self.node = node
        self.identity = try XCTUnwrap(node.retainedViewIdentity, file: file, line: line)
    }

    func assertRetained(as rebuilt: ViewNode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rebuilt.retainedViewIdentity, identity, file: file, line: line)
        XCTAssertTrue(rebuilt === node, file: file, line: line)
    }
}

@MainActor
private final class ViewIdentityRoleHost {
    let runtime: RetainedViewRuntime
    let host: ComponentHost

    convenience init<Content: View>(_ content: @escaping @MainActor () -> Content) {
        self.init(views: { [AnyView(content())] })
    }

    init(views: @escaping @MainActor () -> [AnyView]) {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 400)))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { runtime.root.frame.size },
            invalidateHandler: { [weak host] in host?.reload() })
        self.runtime = runtime
        self.host = host
        host.setComponents { [composeComponent(from: views(), context: context)] }
        _ = runtime.renderFrame()
    }

    var nodes: [ViewNode] {
        runtime.root.children.flatMap { descendants(in: $0) }
    }

    func reload() {
        host.reload()
        _ = runtime.renderFrame()
    }

    func contentRoot(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        XCTAssertEqual(runtime.root.children.count, 1, file: file, line: line)
        return try XCTUnwrap(runtime.root.children.first, file: file, line: line)
    }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node identified as \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func snapshots(_ identifiers: [String]) throws -> [String: ViewIdentityRoleSnapshot] {
        var result: [String: ViewIdentityRoleSnapshot] = [:]
        for identifier in identifiers {
            result[identifier] = try ViewIdentityRoleSnapshot(node(identifier))
        }
        return result
    }

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}
