import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Root-label forwarding through public List declarations and the managed
/// headless host. These do not qualify decoration traversal or native UIA search.
@MainActor
final class ListSelectionLabelTests: XCTestCase {
    func testRootLabelsPreserveNilEmptyAndAuthoredValuesAcrossPublicListForms() async throws {
        let labels: [String?] = [nil, "", "Report.txt, text document"]
        for route in ListSelectionLabelRoute.allCases {
            for label in labels {
                let fixture = ListSelectionLabelFixture(route: route) { index, _ in
                    listSelectionLabelPassiveRow(index, label: label)
                }
                defer { fixture.host.close() }
                XCTAssertNotNil(fixture.host.layout())

                for index in 0..<2 {
                    let content = try fixture.content(index)
                    let owner = try fixture.owner(index)
                    XCTAssertEqual(content.accessibilityLabel, label)
                    XCTAssertEqual(owner.accessibilityLabel, label)
                    XCTAssertNil(owner.accessibilityIdentifier)
                    let projected = try XCTUnwrap(AccessibilityProjection.project(root: owner))
                    XCTAssertEqual(projected.name, label ?? "")
                    XCTAssertEqual(projected.controlType, .listItem)
                }
                XCTAssertNil(fixture.host.coordinator.latestInstallationError)
            }
        }
    }

    func testPassiveFileRowKeepsItsIdentifierAndOneSelectionFocusAndActionOwner() async throws {
        for route in ListSelectionLabelRoute.allCases {
            let fixture = ListSelectionLabelFixture(route: route) { index, probe in
                listSelectionLabelPassiveRow(index, label: probe.name(for: index))
            }
            defer { fixture.host.close() }
            XCTAssertNotNil(fixture.host.layout())
            let owner = try fixture.owner(1)
            let content = try fixture.content(1)
            let subtree = MountedLazyListTestHost.descendants(in: owner)
            XCTAssertTrue(content !== owner)
            XCTAssertEqual(subtree.filter { $0.isFocusable }.count, 1)
            XCTAssertEqual(subtree.filter { $0.onActivate != nil }.count, 1)
            XCTAssertEqual(subtree.filter { $0.accessibilityTraits.contains(.isSelectable) }.count, 1)
            XCTAssertNil(content.onActivate)
            XCTAssertFalse(content.isFocusable)
            XCTAssertNil(owner.accessibilityIdentifier)

            let snapshots = fixture.source.uiaElementSnapshots()
            XCTAssertEqual(snapshots.filter { $0.automationID == fixture.identifier(1) }.count, 1)
            let selected = try fixture.selectionSnapshot(1)
            XCTAssertEqual(selected.name, fixture.probe.name(for: 1))
            XCTAssertTrue(selected.isKeyboardFocusable)
            XCTAssertTrue(selected.hasDefaultAction)
            XCTAssertFalse(selected.supportsValue)
            var focused: [ObjectIdentifier] = []
            fixture.host.runtime.onAccessibilityFocusChanged = { node in
                if let node { focused.append(ObjectIdentifier(node)) }
            }
            fixture.source.uiaSetFocus(elementID: selected.id)
            XCTAssertTrue(fixture.host.runtime.focusedNode === owner)
            XCTAssertEqual(focused, [ObjectIdentifier(owner)])

            let completions = fixture.host.events.rootCompletions
            XCTAssertTrue(fixture.source.uiaSelect(elementID: selected.id))
            XCTAssertEqual(fixture.probe.selected, 1)
            XCTAssertEqual(fixture.probe.selectionWrites, [1])
            XCTAssertEqual(fixture.host.events.rootCompletions, completions + 1)
            XCTAssertNotNil(fixture.host.layout())
            XCTAssertTrue(try fixture.owner(1) === owner)
            XCTAssertTrue(fixture.host.runtime.focusedNode === owner)
            XCTAssertEqual(focused, [ObjectIdentifier(owner)])
            XCTAssertEqual(try fixture.selectionSnapshot(1).id, selected.id)
            XCTAssertEqual(try fixture.selectionSnapshot(1).isSelected, true)
        }
    }

    func testManagedRebuildUpdatesNamesAndSelectionWithoutReplacingPhysicalOwnersOrSourceIDs() async throws {
        for route in ListSelectionLabelRoute.allCases {
            let fixture = ListSelectionLabelFixture(route: route) { index, probe in
                listSelectionLabelPassiveRow(index, label: probe.name(for: index))
            }
            defer { fixture.host.close() }
            XCTAssertNotNil(fixture.host.layout())
            let before = try [fixture.owner(0), fixture.owner(1)]
            let identities = before.map(\.retainedViewIdentity)
            let sourceIDs = try [fixture.selectionSnapshot(0).id, fixture.selectionSnapshot(1).id]

            fixture.probe.namePrefix = "Renamed document"
            fixture.probe.selected = 1
            fixture.host.reload()
            XCTAssertNotNil(fixture.host.layout())

            for index in 0..<2 {
                let owner = try fixture.owner(index)
                let snapshot = try fixture.selectionSnapshot(index)
                XCTAssertTrue(owner === before[index])
                XCTAssertEqual(owner.retainedViewIdentity, identities[index])
                XCTAssertEqual(owner.accessibilityLabel, fixture.probe.name(for: index))
                XCTAssertEqual(snapshot.name, fixture.probe.name(for: index))
                XCTAssertEqual(snapshot.id, sourceIDs[index])
                XCTAssertEqual(snapshot.isSelected, index == 1)
                XCTAssertEqual(try fixture.content(index).accessibilityIdentifier, fixture.identifier(index))
                XCTAssertNil(owner.accessibilityIdentifier)
            }
            XCTAssertTrue(fixture.probe.selectionWrites.isEmpty)
            XCTAssertNil(fixture.host.coordinator.latestInstallationError)
        }
    }

    func testMissingRootNamesDoNotScrapeTextDescendantsBackgroundsOrEditorValues() async throws {
        for route in ListSelectionLabelRoute.allCases {
            for kind in ListSelectionLabelUnnamedContent.allCases {
                let fixture = ListSelectionLabelFixture(route: route) { index, probe in
                    kind.makeRow(index, probe: probe)
                }
                defer { fixture.host.close() }
                XCTAssertNotNil(fixture.host.layout())
                let content = try fixture.content(0)
                let owner = try fixture.owner(0)
                XCTAssertTrue(content.accessibilityLabel?.isEmpty != false)
                XCTAssertEqual(owner.accessibilityLabel, content.accessibilityLabel)
                XCTAssertNil(owner.accessibilityValue)
                XCTAssertNil(owner.textInputController)
                let projected = try XCTUnwrap(AccessibilityProjection.project(root: owner))
                XCTAssertEqual(projected.name, "")

                let snapshots = fixture.source.uiaElementSnapshots()
                let selection = snapshots.filter { $0.isSelected != nil }
                XCTAssertEqual(selection.count, 2)
                XCTAssertTrue(selection.allSatisfy { $0.name.isEmpty && $0.value == nil && !$0.supportsValue })
                if kind == .secure {
                    XCTAssertFalse(
                        snapshots.contains {
                            $0.name.contains(ListSelectionLabelProbe.secret)
                                || $0.value?.contains(ListSelectionLabelProbe.secret) == true
                        })
                }
            }
        }
    }

    func testInteractiveRootNamesDoNotMoveControlCapabilitiesOrHandlersToSelection() async throws {
        for route in ListSelectionLabelRoute.allCases {
            for kind in ListSelectionLabelInteractiveContent.allCases {
                let fixture = ListSelectionLabelFixture(route: route) { index, probe in
                    kind.makeRow(index, probe: probe)
                }
                defer { fixture.host.close() }
                XCTAssertNotNil(fixture.host.layout())
                let content = try fixture.content(0)
                let owner = try fixture.owner(0)
                XCTAssertEqual(owner.accessibilityLabel, fixture.probe.name(for: 0))
                XCTAssertNil(owner.accessibilityIdentifier)
                XCTAssertNil(owner.accessibilityValue)
                XCTAssertNil(owner.accessibilityChildBehavior)
                XCTAssertNil(owner.textInputController)
                XCTAssertTrue(owner.accessibilityActions.isEmpty)
                XCTAssertFalse(owner.accessibilityTraits.contains(.isButton))
                XCTAssertFalse(owner.accessibilityTraits.contains(.isToggle))
                XCTAssertFalse(owner.accessibilityTraits.contains(.isTextInput))
                XCTAssertFalse(owner.accessibilityTraits.contains(.isSecureTextInput))
                XCTAssertEqual(AccessibilityProjection.resolveControlType(for: owner), .listItem)
                let selected = try fixture.selectionSnapshot(0)
                XCTAssertFalse(selected.supportsValue)
                XCTAssertNil(selected.value)
                XCTAssertNil(selected.toggleState)
                XCTAssertFalse(selected.isPassword)
                let child = try fixture.contentSnapshot(0)

                switch kind {
                case .button:
                    XCTAssertTrue(content.accessibilityTraits.contains(.isButton))
                    XCTAssertEqual(content.accessibilityChildBehavior, .combine)
                    XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: child.id))
                    XCTAssertEqual(fixture.probe.controlCalls, 1)
                case .toggle:
                    XCTAssertTrue(content.accessibilityTraits.contains(.isToggle))
                    XCTAssertTrue(fixture.source.uiaToggle(elementID: child.id))
                    XCTAssertTrue(fixture.probe.isOn)
                case .editor:
                    XCTAssertNotNil(content.textInputController)
                    XCTAssertTrue(child.supportsValue)
                    XCTAssertTrue(fixture.source.uiaSetValue(elementID: child.id, value: "Edited child value"))
                    XCTAssertEqual(fixture.probe.editorValue, "Edited child value")
                case .secure:
                    XCTAssertNotNil(content.textInputController)
                    XCTAssertTrue(child.isPassword)
                    XCTAssertFalse(child.supportsValue)
                    XCTAssertNil(child.value)
                    XCTAssertFalse(fixture.source.uiaSetValue(elementID: child.id, value: "Replacement"))
                case .customAction:
                    XCTAssertEqual(content.accessibilityChildBehavior, .combine)
                    XCTAssertEqual(content.accessibilityValue, "Child-only value")
                    XCTAssertEqual(content.accessibilityActions.count, 1)
                    XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: child.id))
                    XCTAssertEqual(fixture.probe.controlCalls, 1)
                }
                XCTAssertTrue(fixture.probe.selectionWrites.isEmpty)
                let calls = fixture.probe.controlCalls
                let isOn = fixture.probe.isOn
                let editorValue = fixture.probe.editorValue
                XCTAssertTrue(fixture.source.uiaSelect(elementID: try fixture.selectionSnapshot(0).id))
                XCTAssertEqual(fixture.probe.selectionWrites, [0])
                XCTAssertEqual(fixture.probe.controlCalls, calls)
                XCTAssertEqual(fixture.probe.isOn, isOn)
                XCTAssertEqual(fixture.probe.editorValue, editorValue)
            }
        }
    }

    func testHiddenRootLabelsAreNotRecoveredOnTheVisibleSelectionWrapper() async throws {
        for route in ListSelectionLabelRoute.allCases {
            for accessibilityOnly in [false, true] {
                let fixture = ListSelectionLabelFixture(route: route) { index, _ in
                    let content = listSelectionLabelPassiveRow(index, label: "Suppressed document")
                    if accessibilityOnly { return AnyView(content.accessibilityHidden(true)) }
                    return AnyView(content.hidden())
                }
                defer { fixture.host.close() }
                XCTAssertNotNil(fixture.host.layout())
                let content = try fixture.content(0)
                XCTAssertEqual(content.accessibilityLabel, "Suppressed document")
                XCTAssertTrue(accessibilityOnly ? content.isAccessibilityHidden : content.isHidden)
                XCTAssertNil(try fixture.owner(0).accessibilityLabel)
                XCTAssertFalse(fixture.source.uiaElementSnapshots().contains { $0.name == "Suppressed document" })
                // Hiding the new wrapper itself is not part of this label-only port.
            }
        }
    }

    func testTenThousandDataRowsNameOnlyMaterializedRowsWithoutExtraFactories() async throws {
        for route in ListSelectionLabelRoute.deferred {
            let fixture = ListSelectionLabelFixture(
                route: route, count: 10_000, size: Size(width: 360, height: 80)
            ) { index, probe in
                listSelectionLabelPassiveRow(index, label: probe.name(for: index))
            }
            defer { fixture.host.close() }
            try fixture.host.assertCommittedDescriptor()
            XCTAssertTrue(fixture.probe.factoryCalls.isEmpty)
            let adapter = try XCTUnwrap(try fixture.host.list().retainedLazyListAdapter)
            XCTAssertEqual(adapter.mountedRecordCount, 0)
            XCTAssertNotNil(fixture.host.layout())
            XCTAssertEqual(adapter.logicalRecordCount, 10_000)
            XCTAssertFalse(fixture.probe.factoryCalls.isEmpty)
            XCTAssertLessThan(fixture.probe.factoryCalls.count, 128)
            XCTAssertLessThan(adapter.mountedRecordCount, 32)

            let owners = fixture.host.nodes.filter { $0.accessibilityTraits.contains(.isSelectable) }
            XCTAssertFalse(owners.isEmpty)
            let mountedNames = Set(owners.compactMap(\.accessibilityLabel))
            let factories = fixture.probe.factoryCalls
            let snapshots = fixture.source.uiaElementSnapshots()
            let selectionNames = Set(snapshots.filter { $0.isSelected != nil }.map(\.name))
            XCTAssertEqual(fixture.probe.factoryCalls, factories)
            XCTAssertTrue(selectionNames.isSubset(of: mountedNames))
            XCTAssertTrue(selectionNames.contains(fixture.probe.name(for: 0)))
            XCTAssertNil(fixture.host.find(fixture.identifier(9000)))
            XCTAssertFalse(fixture.probe.factoryCalls.contains(9000))
            XCTAssertFalse(snapshots.contains { $0.name == fixture.probe.name(for: 9000) })
            XCTAssertNil(fixture.host.coordinator.latestInstallationError)
        }
    }

    func testEvictedRowReconstructsItsStateBackedLabelWithoutRevivingOldActivation() async throws {
        for route in ListSelectionLabelRoute.deferred {
            let fixture = ListSelectionLabelFixture(
                route: route, count: 1000, size: Size(width: 360, height: 80)
            ) { index, probe in
                AnyView(ListSelectionLabelStatefulRow(index: index, probe: probe))
            }
            defer { fixture.host.close() }
            XCTAssertNotNil(fixture.host.layout())
            let original = try XCTUnwrap(fixture.probe.captures[0])
            let generation = original.owner.generation
            let departed = try fixture.captureDeparture(0)
            let initialFactories = fixture.probe.factoryCalls.filter { $0 == 0 }.count

            try fixture.host.scroll(to: 4000)
            XCTAssertNil(fixture.host.find(fixture.identifier(0)))
            XCTAssertFalse(departed.attachment.isCurrent)
            XCTAssertNil(departed.node.value)
            XCTAssertTrue(original.owner.isLive)
            let writes = fixture.probe.selectionWrites
            let completions = fixture.host.events.rootCompletions
            let factories = fixture.probe.factoryCalls
            departed.activate()
            XCTAssertEqual(fixture.probe.selectionWrites, writes)
            XCTAssertEqual(fixture.host.events.rootCompletions, completions)
            XCTAssertEqual(fixture.probe.factoryCalls, factories)

            original.label.wrappedValue = "Renamed while offscreen"
            XCTAssertNotNil(fixture.host.layout())
            XCTAssertNil(fixture.host.find(fixture.identifier(0)))
            XCTAssertEqual(fixture.probe.factoryCalls.filter { $0 == 0 }.count, initialFactories)
            try fixture.host.scroll(to: 0)
            let returned = try XCTUnwrap(fixture.probe.captures[0])
            XCTAssertTrue(returned.owner === original.owner)
            XCTAssertEqual(returned.owner.generation, generation)
            XCTAssertEqual(returned.label.wrappedValue, "Renamed while offscreen")
            XCTAssertEqual(try fixture.owner(0).accessibilityLabel, "Renamed while offscreen")
            XCTAssertGreaterThan(fixture.probe.factoryCalls.filter { $0 == 0 }.count, initialFactories)
            XCTAssertNil(departed.node.value)
            XCTAssertFalse(departed.attachment.isCurrent)
            departed.activate()
            XCTAssertEqual(fixture.probe.selectionWrites, writes)
            try XCTUnwrap(try fixture.owner(0).onActivate)()
            XCTAssertEqual(fixture.probe.selectionWrites, [0])
            XCTAssertEqual(try fixture.owner(0).accessibilityLabel, "Renamed while offscreen")
            XCTAssertNil(fixture.host.coordinator.latestInstallationError)
        }
    }
}

private enum ListSelectionLabelRoute: CaseIterable {
    case literal
    case data
    case builder

    static let deferred: [Self] = [.data, .builder]
}

@MainActor
private final class ListSelectionLabelProbe {
    static let secret = "secure-value-do-not-copy"
    let rows: [Int]
    var selected: Int?
    var selectionWrites: [Int?] = []
    var factoryCalls: [Int] = []
    var namePrefix = "Document"
    var controlCalls = 0
    var isOn = false
    var editorValue = "Private editor contents"
    var captures: [Int: ListSelectionLabelCapture] = [:]

    init(count: Int) { rows = Array(0..<count) }

    func name(for index: Int) -> String { "\(namePrefix) \(index), text file" }

    var selection: Binding<Int?> {
        Binding(
            get: { self.selected },
            set: {
                self.selected = $0
                self.selectionWrites.append($0)
            })
    }

    var text: Binding<String> {
        Binding(get: { self.editorValue }, set: { self.editorValue = $0 })
    }

    var toggle: Binding<Bool> {
        Binding(get: { self.isOn }, set: { self.isOn = $0 })
    }

    func capture(index: Int, label: Binding<String>) {
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            XCTFail("A state-backed row label must have a mounted owner")
            return
        }
        captures[index] = ListSelectionLabelCapture(owner: owner, label: label)
    }
}

@MainActor
private final class ListSelectionLabelFixture {
    let probe: ListSelectionLabelProbe
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource

    init(
        route: ListSelectionLabelRoute, count: Int = 2, size: Size = Size(width: 360, height: 180),
        row: @escaping @MainActor (Int, ListSelectionLabelProbe) -> AnyView
    ) {
        let probe = ListSelectionLabelProbe(count: count)
        self.probe = probe
        let factory: @MainActor (Int) -> AnyView = { index in
            probe.factoryCalls.append(index)
            return AnyView(
                row(index, probe)
                    .accessibilityIdentifier("selection-label.content.\(index)")
                    .id(index))
        }
        host = MountedLazyListTestHost(size: size) { listSelectionLabelList(probe, route: route, row: factory) }
        source = RuntimeUIAElementTreeSource(runtime: host.runtime)
    }

    func identifier(_ index: Int) -> String { "selection-label.content.\(index)" }

    func content(_ index: Int, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = host.nodes.filter { $0.accessibilityIdentifier == identifier(index) }
        XCTAssertEqual(matches.count, 1, "Content identifiers must not migrate to selection", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func owner(_ index: Int, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let content = try content(index, file: file, line: line)
        var ancestor = content.parent
        var owners: [ViewNode] = []
        while let node = ancestor {
            if node.accessibilityTraits.contains(.isSelectable) { owners.append(node) }
            ancestor = node.parent
        }
        XCTAssertEqual(owners.count, 1, "Each content root has one selectable ancestor", file: file, line: line)
        return try XCTUnwrap(owners.first, file: file, line: line)
    }

    func selectionSnapshot(_ index: Int, file: StaticString = #filePath, line: UInt = #line) throws
        -> UIAElementSnapshot
    {
        let name = try XCTUnwrap(try owner(index, file: file, line: line).accessibilityLabel, file: file, line: line)
        let matches = source.uiaElementSnapshots().filter { $0.isSelected != nil && $0.name == name }
        XCTAssertEqual(matches.count, 1, "Expected one named selection owner", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func contentSnapshot(_ index: Int, file: StaticString = #filePath, line: UInt = #line) throws -> UIAElementSnapshot
    {
        let matches = source.uiaElementSnapshots().filter { $0.automationID == identifier(index) }
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        let snapshot = try XCTUnwrap(matches.first, file: file, line: line)
        XCTAssertNil(snapshot.isSelected, file: file, line: line)
        return snapshot
    }

    @inline(never)
    func captureDeparture(_ index: Int) throws -> ListSelectionLabelDeparture {
        let owner = try owner(index)
        return ListSelectionLabelDeparture(
            node: ListSelectionLabelWeakNode(owner), attachment: owner.captureLazyListAttachmentProof(),
            activate: try XCTUnwrap(owner.onActivate))
    }
}

@MainActor
@ViewBuilder
private func listSelectionLabelList(
    _ probe: ListSelectionLabelProbe, route: ListSelectionLabelRoute, row: @escaping @MainActor (Int) -> AnyView
) -> some View {
    switch route {
    case .literal:
        List(selection: probe.selection) {
            row(0).tag(0)
            row(1).tag(1)
        }
        .listStyle(.plain)
    case .data:
        List(probe.rows, id: \.self, selection: probe.selection) { row($0) }
            .listStyle(.plain)
    case .builder:
        List(selection: probe.selection) {
            ForEach(probe.rows, id: \.self) { row($0).tag($0) }
        }
        .listStyle(.plain)
    }
}

@MainActor
private func listSelectionLabelPassiveRow(_ index: Int, label: String?) -> AnyView {
    let content = HStack(spacing: 8) {
        Image(systemName: "doc.text")
        VStack(alignment: .leading, spacing: 2) {
            Text("Report-\(index).txt")
            Text("Text document")
        }
        Spacer()
    }
    .frame(height: 32)
    if let label { return AnyView(content.accessibilityLabel(label)) }
    return AnyView(content)
}

private enum ListSelectionLabelUnnamedContent: CaseIterable {
    case plainText
    case descendant
    case background
    case editor
    case secure

    @MainActor
    func makeRow(_ index: Int, probe: ListSelectionLabelProbe) -> AnyView {
        switch self {
        case .plainText:
            return AnyView(Text("Plain text is not an authored root name \(index)"))
        case .descendant:
            return AnyView(HStack { Text("Child").accessibilityLabel("Descendant name \(index)") })
        case .background:
            return AnyView(
                Text("Foreground").frame(height: 24)
                    .background(Text("Backdrop").accessibilityLabel("Background name \(index)")))
        case .editor:
            return AnyView(TextField("", text: probe.text))
        case .secure:
            return AnyView(SecureField("", text: .constant(ListSelectionLabelProbe.secret)))
        }
    }
}

private enum ListSelectionLabelInteractiveContent: CaseIterable {
    case button
    case toggle
    case editor
    case secure
    case customAction

    @MainActor
    func makeRow(_ index: Int, probe: ListSelectionLabelProbe) -> AnyView {
        let content: AnyView
        switch self {
        case .button:
            content = AnyView(Button("Inspect") { probe.controlCalls += 1 })
        case .toggle:
            content = AnyView(Toggle("Enabled", isOn: probe.toggle).labelsHidden())
        case .editor:
            content = AnyView(TextField("Name", text: probe.text))
        case .secure:
            content = AnyView(SecureField("Password", text: .constant(ListSelectionLabelProbe.secret)))
        case .customAction:
            content = AnyView(
                Text("Custom action").accessibilityElement(children: .combine)
                    .accessibilityValue("Child-only value")
                    .accessibilityAction { probe.controlCalls += 1 })
        }
        return AnyView(content.accessibilityLabel(probe.name(for: index)))
    }
}

@MainActor
private struct ListSelectionLabelCapture {
    let owner: StateMountOwner
    let label: Binding<String>
}

@MainActor
private struct ListSelectionLabelStatefulRow: View {
    @State private var label: String
    let index: Int
    let probe: ListSelectionLabelProbe

    init(index: Int, probe: ListSelectionLabelProbe) {
        self.index = index
        self.probe = probe
        _label = State(initialValue: probe.name(for: index))
    }

    var body: some View {
        probe.capture(index: index, label: $label)
        return listSelectionLabelPassiveRow(index, label: label)
    }
}

@MainActor
private struct ListSelectionLabelDeparture {
    let node: ListSelectionLabelWeakNode
    let attachment: RetainedLazyListAttachmentProof
    let activate: () -> Void
}

@MainActor
private final class ListSelectionLabelWeakNode {
    weak var value: ViewNode?
    init(_ value: ViewNode) { self.value = value }
}
