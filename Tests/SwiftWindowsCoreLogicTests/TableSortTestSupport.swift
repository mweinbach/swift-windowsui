import CUIAInterop
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

struct TableSortTestRow: Identifiable, Equatable {
    let id: Int
    let name: String
}

struct TableSortTestColumn {
    let id: String
    var title: String
    var key: AnyHashable?
    var sortable = true
    var width: TableColumnWidth = .fixed(160)
    var label: String?
    var authoredID: String?
    var emptyHeader = false
}

struct TableSortTestRequest: Equatable {
    let key: AnyHashable?
    let order: WinSwiftUI.SortOrder
}

@MainActor
final class TableSortTestModel {
    var rows = [TableSortTestRow(id: 2, name: "Zulu"), TableSortTestRow(id: 1, name: "Alpha")]
    var columns = [
        TableSortTestColumn(id: "name", title: "Name", key: "name"),
        TableSortTestColumn(id: "number", title: "Number", key: "number"),
    ]
    var selection: Int? = 2
    var selections: Set<Int> = [2]
    var selectionWrites = 0
    var usesMultipleSelection = false
    var hasSelection = true
    var sort: (key: AnyHashable, order: WinSwiftUI.SortOrder)?
    var onSort: ((AnyHashable?, WinSwiftUI.SortOrder) -> Void)?
    var requests: [TableSortTestRequest] = []
    var isEnabled = true
    var isPresent = true
    var headerBuilds: [String: Int] = [:]
    var builds = 0

    init() {
        onSort = { [weak self] key, order in
            self?.requests.append(TableSortTestRequest(key: key, order: order))
        }
    }

    func column(_ value: TableSortTestColumn) -> AnyTableColumn<TableSortTestRow> {
        AnyTableColumn(
            title: value.title, width: value.width, sortKey: value.key, isSortable: value.sortable,
            cellBuilder: { row in
                [AnyView(Text(row.name).accessibilityIdentifier("cell.\(value.id).\(row.id)"))]
            },
            headerBuilder: { [self] in
                headerBuilds[value.id, default: 0] += 1
                guard !value.emptyHeader else { return [] }
                let content = AnyView(Text(value.title).accessibilityIdentifier("heading.\(value.id)"))
                let labeled = value.label.map { AnyView(content.accessibilityLabel($0)) } ?? content
                return [value.authoredID.map { AnyView(labeled.id($0)) } ?? labeled]
            })
    }

    func view() -> AnyView {
        guard isPresent else { return AnyView(EmptyView()) }
        if usesMultipleSelection {
            return AnyView(
                Table(
                    rows,
                    selection: Binding<Set<Int>>(
                        get: { self.selections },
                        set: {
                            self.selections = $0
                            self.selectionWrites += 1
                        }),
                    sort: sort, onSort: onSort
                ) {
                    for value in columns { column(value) }
                }
                .disabled(!isEnabled)
                .accessibilityIdentifier("table.sort.fixture"))
        }
        return AnyView(
            Table(
                rows,
                selection: hasSelection
                    ? Binding<Int?>(
                        get: { self.selection },
                        set: {
                            self.selection = $0
                            self.selectionWrites += 1
                        }) : nil,
                sort: sort, onSort: onSort
            ) {
                for value in columns { column(value) }
            }
            .disabled(!isEnabled)
            .accessibilityIdentifier("table.sort.fixture"))
    }
}

/// A real managed retained tree. No HWND, COM provider, renderer backend,
/// native keyboard injection, or file/dialog service is created by this fixture.
@MainActor
final class TableSortTestFixture {
    let model: TableSortTestModel
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let coordinator: StateMountCoordinator
    let source: RuntimeUIAElementTreeSource

    init(model: TableSortTestModel = TableSortTestModel(), view: (@MainActor () -> AnyView)? = nil) {
        self.model = model
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 600, height: 320)))
        self.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() },
            observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        self.coordinator = coordinator
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        host.buildLifecycle = coordinator
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator,
            canvasSizeProvider: { runtime.root.frame.size },
            invalidateHandler: { [weak host] in host?.reload() })
        host.setComponents {
            model.builds += 1
            return [makeViewComponent(view?() ?? model.view(), context: context)]
        }
        settle()
    }

    func close() {
        runtime.stopRenderLifecycleCallbacks()
        coordinator.close()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }

    func settle(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root), file: file, line: line)
        XCTAssertNil(coordinator.latestInstallationError, file: file, line: line)
    }

    func reload() {
        host.reload()
        settle()
    }

    func table(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        try node("table.sort.fixture", file: file, line: line)
    }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes(in: runtime.root).filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, identifier, file: file, line: line)
        return try XCTUnwrap(matches.first, identifier, file: file, line: line)
    }

    func header(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let index = try XCTUnwrap(model.columns.firstIndex { $0.id == id }, file: file, line: line)
        let row = try XCTUnwrap(try table(file: file, line: line).children.first, file: file, line: line)
        XCTAssertEqual(row.children.count, model.columns.count, file: file, line: line)
        return try XCTUnwrap(row.children.indices.contains(index) ? row.children[index] : nil, file: file, line: line)
    }

    func button(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let root = try header(id, file: file, line: line)
        XCTAssertTrue(root.accessibilityTraits.contains(.isButton), file: file, line: line)
        XCTAssertNotNil(root.onActivate, file: file, line: line)
        XCTAssertTrue(root.isFocusable, file: file, line: line)
        return root
    }

    func snapshot(named name: String, file: StaticString = #filePath, line: UInt = #line) throws -> UIAElementSnapshot {
        let matches = source.uiaElementSnapshots().filter {
            $0.name == name && $0.controlType == Int32(SWU_UIA_CONTROL_TYPE_BUTTON)
        }
        XCTAssertEqual(matches.count, 1, name, file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func click(_ node: ViewNode, file: StaticString = #filePath, line: UInt = #line) throws {
        let frame = try XCTUnwrap(runtime.resolvedLayoutFrame(of: node), file: file, line: line)
        XCTAssertGreaterThan(frame.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(frame.size.height, 0, file: file, line: line)
        let point = Point(x: frame.midX, y: frame.midY)
        runtime.pointerMoved(to: point)
        runtime.pointerDown(at: point)
        runtime.pointerUp(at: point)
    }

    func key(_ code: UInt32, on node: ViewNode, file: StaticString = #filePath, line: UInt = #line) {
        runtime.requestFocus(node)
        XCTAssertTrue(runtime.focusedNode === node, file: file, line: line)
        runtime.keyDown(KeyboardEvent(keyCode: code, modifiers: []))
    }

    func nodes(in root: ViewNode) -> [ViewNode] {
        var result: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
}
