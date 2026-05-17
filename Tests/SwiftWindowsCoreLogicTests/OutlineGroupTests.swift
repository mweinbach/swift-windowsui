import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
@testable import SwiftWindowsUI
@testable import WinSwiftUI
import Testing

@MainActor
@Suite("OutlineGroup Tests")
struct OutlineGroupTests {

    struct TreeItem: Identifiable {
        let id: String
        let name: String
        var children: [TreeItem]?
    }

    @Test("OutlineGroup renders leaf items without chevron")
    func outlineGroupRendersLeaves() async {
        let items = [
            TreeItem(id: "a", name: "Alpha", children: nil),
            TreeItem(id: "b", name: "Beta", children: nil)
        ]

        let group = OutlineGroup(items, children: \.children) { item in
            Text(item.name)
        }

        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 400) },
            invalidateHandler: {}
        )
        let component = group.makeComponent(context: context)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = component.makeNode(runtime: runtime)

        #expect(node.children.count == 2)
    }

    @Test("OutlineGroup renders parent items with expandable children")
    func outlineGroupRendersParents() async {
        let items = [
            TreeItem(id: "root", name: "Root", children: [
                TreeItem(id: "child1", name: "Child 1", children: nil),
                TreeItem(id: "child2", name: "Child 2", children: nil)
            ])
        ]

        let group = OutlineGroup(items, children: \.children) { item in
            Text(item.name)
        }

        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 400) },
            invalidateHandler: {}
        )
        let component = group.makeComponent(context: context)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = component.makeNode(runtime: runtime)

        // Top level should have 1 parent row (collapsed by default)
        #expect(node.children.count == 1)
        let parentRow = node.children[0]
        // Parent row is a stack panel containing the header button
        #expect(parentRow.children.count == 1)
    }

    @Test("OutlineGroup single root init")
    func outlineGroupSingleRoot() async {
        let root = TreeItem(id: "root", name: "Root", children: [
            TreeItem(id: "c1", name: "Child 1", children: nil)
        ])

        let group = OutlineGroup(root, children: \.children) { item in
            Text(item.name)
        }

        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 400) },
            invalidateHandler: {}
        )
        let component = group.makeComponent(context: context)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = component.makeNode(runtime: runtime)

        #expect(node.children.count == 1)
    }

    @Test("OutlineGroup explicit ID init")
    func outlineGroupExplicitID() async {
        struct NonIdentifiableItem {
            let key: String
            let name: String
            var children: [NonIdentifiableItem]?
        }

        let items = [
            NonIdentifiableItem(key: "a", name: "Alpha", children: nil),
            NonIdentifiableItem(key: "b", name: "Beta", children: [
                NonIdentifiableItem(key: "b1", name: "Beta 1", children: nil)
            ])
        ]

        let group = OutlineGroup(items, id: \.key, children: \.children) { item in
            Text(item.name)
        }

        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 400) },
            invalidateHandler: {}
        )
        let component = group.makeComponent(context: context)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = component.makeNode(runtime: runtime)

        #expect(node.children.count == 2)
    }

    @Test("List with children renders hierarchical OutlineGroup")
    func listWithChildrenRendersHierarchically() async {
        let items = [
            TreeItem(id: "r", name: "Root", children: [
                TreeItem(id: "c1", name: "Child 1", children: nil)
            ])
        ]

        let list = List(items, children: \.children) { item in
            Text(item.name)
        }

        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 400) },
            invalidateHandler: {}
        )
        let component = list.makeComponent(context: context)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = component.makeNode(runtime: runtime)

        // List wraps content in a scroll panel
        #expect(node.children.count == 1)
    }

    @Test("List with children and single selection renders")
    func listWithChildrenAndSelection() async {
        let items = [
            TreeItem(id: "r", name: "Root", children: [
                TreeItem(id: "c1", name: "Child 1", children: nil)
            ])
        ]

        var selection: String? = nil
        let binding = Binding(get: { selection }, set: { selection = $0 })

        let list = List(items, children: \.children, selection: binding) { item in
            Text(item.name)
        }

        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 400) },
            invalidateHandler: {}
        )
        let component = list.makeComponent(context: context)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = component.makeNode(runtime: runtime)

        // Should render without crashing
        #expect(node.children.count == 1)
    }

    @Test("List with children and multiple selection renders")
    func listWithChildrenAndMultipleSelection() async {
        let items = [
            TreeItem(id: "r", name: "Root", children: [
                TreeItem(id: "c1", name: "Child 1", children: nil)
            ])
        ]

        var selection = Set<String>()
        let binding = Binding(get: { selection }, set: { selection = $0 })

        let list = List(items, children: \.children, selection: binding) { item in
            Text(item.name)
        }

        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 400) },
            invalidateHandler: {}
        )
        let component = list.makeComponent(context: context)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = component.makeNode(runtime: runtime)

        // Should render without crashing
        #expect(node.children.count == 1)
    }
}
