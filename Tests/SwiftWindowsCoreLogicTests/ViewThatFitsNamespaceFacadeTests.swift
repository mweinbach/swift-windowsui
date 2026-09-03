import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsNamespaceFacadeTests: XCTestCase {
    func testInitiallySelectedEmptyOutputStateSurvivesDormancyButNotAnOmittedIdentity() async throws {
        let probe = ViewThatFitsNamespaceProbe()
        var leadingFits = false
        var identifier = "original"
        var seed = 13
        let host = MountedOnChangeTestHost {
            probe.outerBuilds += 1
            return AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: leadingFits ? 10 : 1_000, height: 20)
                    ViewThatFitsNamespaceEmptyState(seed: seed, probe: probe).id(identifier)
                })
        }
        defer { host.close() }
        host.render()
        let original = try probe.binding("empty")
        XCTAssertEqual(original.wrappedValue, 13)

        original.wrappedValue = 17
        host.render()
        XCTAssertEqual(original.wrappedValue, 17)
        XCTAssertEqual(try probe.binding("empty").wrappedValue, 17)

        let dormantBuilds = probe.bodyBuilds["empty", default: 0]
        leadingFits = true
        host.reload()
        host.render()
        XCTAssertEqual(probe.bodyBuilds["empty", default: 0], dormantBuilds)
        original.wrappedValue = 19
        host.render()
        XCTAssertEqual(original.wrappedValue, 19)
        XCTAssertEqual(probe.bodyBuilds["empty", default: 0], dormantBuilds)

        identifier = "replacement"
        host.reload()
        host.render()
        XCTAssertEqual(probe.bodyBuilds["empty", default: 0], dormantBuilds)
        assertNamespaceWriteIsRejected(original, lastValue: 19, probe: probe, host: host)

        identifier = "original"
        seed = 37
        host.reload()
        host.render()
        XCTAssertEqual(probe.bodyBuilds["empty", default: 0], dormantBuilds)
        assertNamespaceWriteIsRejected(original, lastValue: 19, probe: probe, host: host)

        leadingFits = false
        host.reload()
        host.render()
        let replacement = try probe.binding("empty")
        XCTAssertEqual(replacement.wrappedValue, 37)
        replacement.wrappedValue = 41
        host.render()
        XCTAssertEqual(replacement.wrappedValue, 41)
        XCTAssertEqual(try probe.binding("empty").wrappedValue, 41)
        assertNamespaceWriteIsRejected(original, lastValue: 19, probe: probe, host: host)
        XCTAssertEqual(replacement.wrappedValue, 41)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testInitiallySelectedZeroSlotOwnerRetiresOnlyWhenItsInactiveIdentityIsOmitted() async throws {
        let probe = ViewThatFitsNamespaceProbe()
        var leadingFits = false
        var identifier = "original"
        let host = MountedOnChangeTestHost {
            probe.outerBuilds += 1
            return AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: leadingFits ? 10 : 1_000, height: 20)
                    ViewThatFitsNamespaceZeroSlotOwner(probe: probe).id(identifier)
                })
        }
        defer { host.close() }
        host.render()
        let original = try XCTUnwrap(probe.zeroSlotOwner)
        XCTAssertTrue(original.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: original.identity) === original)

        let dormantBuilds = probe.bodyBuilds["zero", default: 0]
        leadingFits = true
        host.reload()
        host.render()
        XCTAssertEqual(probe.bodyBuilds["zero", default: 0], dormantBuilds)
        XCTAssertTrue(original.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: original.identity) === original)

        identifier = "replacement"
        host.reload()
        host.render()
        XCTAssertEqual(probe.bodyBuilds["zero", default: 0], dormantBuilds)
        XCTAssertFalse(original.isLive)
        XCTAssertNil(host.coordinator.registry.owner(at: original.identity))

        identifier = "original"
        host.reload()
        host.render()
        XCTAssertEqual(probe.bodyBuilds["zero", default: 0], dormantBuilds)
        XCTAssertFalse(original.isLive)
        XCTAssertNil(host.coordinator.registry.owner(at: original.identity))

        leadingFits = false
        host.reload()
        host.render()
        let replacement = try XCTUnwrap(probe.zeroSlotOwner)
        XCTAssertFalse(replacement === original)
        XCTAssertNotEqual(replacement.generation, original.generation)
        XCTAssertTrue(replacement.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: replacement.identity) === replacement)
        XCTAssertFalse(original.isLive)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testNestedDeferredCandidatesKeepOnlyAcceptedStateAcrossOuterDormancyAndLocalResize() async throws {
        let probe = ViewThatFitsNamespaceProbe()
        var outerLeadingFits = false
        var primaryFits = false
        let host = MountedOnChangeTestHost(size: Size(width: 600, height: 240)) {
            probe.outerBuilds += 1
            return AnyView(
                GeometryReader { _ in
                    let _ = probe.recordReader("outer")
                    ViewThatFits(in: .horizontal) {
                        Color.clear
                            .frame(width: outerLeadingFits ? 10 : 1_200, height: 20)
                            .accessibilityIdentifier("namespace.outer.leading")
                        ViewThatFits(in: .horizontal) {
                            GeometryReader { _ in
                                let _ = probe.recordReader("primary")
                                ViewThatFitsNamespaceCounter(name: "primary", seed: 10, probe: probe)
                            }
                            .frame(width: primaryFits ? 180 : 1_000, height: 40)
                            GeometryReader { _ in
                                let _ = probe.recordReader("fallback")
                                ViewThatFitsNamespaceCounter(name: "fallback", seed: 20, probe: probe)
                            }
                            .frame(width: 180, height: 40)
                        }
                    }
                })
        }
        defer { host.close() }
        host.render()
        let rejected = try probe.binding("primary")
        let fallback = try probe.binding("fallback")
        XCTAssertFalse(namespaceContains("primary", host: host))
        XCTAssertEqual(try namespaceNode("fallback", host: host).text, "20")
        assertNamespaceWriteIsRejected(rejected, lastValue: 10, probe: probe, host: host)

        fallback.wrappedValue = 21
        host.render()
        XCTAssertEqual(try namespaceNode("fallback", host: host).text, "21")

        primaryFits = true
        host.reload()
        host.render()
        let primary = try probe.binding("primary")
        XCTAssertEqual(try namespaceNode("primary", host: host).text, "10")
        XCTAssertFalse(namespaceContains("fallback", host: host))
        primary.wrappedValue = 11
        host.render()
        XCTAssertEqual(try namespaceNode("primary", host: host).text, "11")

        outerLeadingFits = true
        host.reload()
        host.render()
        XCTAssertTrue(namespaceContains("outer.leading", host: host))
        XCTAssertFalse(namespaceContains("primary", host: host))
        XCTAssertFalse(namespaceContains("fallback", host: host))
        let dormantBodies = probe.bodyBuilds
        let dormantPrimaryReaders = probe.readerBuilds["primary", default: 0]
        let dormantFallbackReaders = probe.readerBuilds["fallback", default: 0]

        primary.wrappedValue = 12
        host.render()
        fallback.wrappedValue = 22
        host.render()
        XCTAssertEqual(primary.wrappedValue, 12)
        XCTAssertEqual(fallback.wrappedValue, 22)
        XCTAssertEqual(probe.bodyBuilds, dormantBodies)
        XCTAssertEqual(probe.readerBuilds["primary", default: 0], dormantPrimaryReaders)
        XCTAssertEqual(probe.readerBuilds["fallback", default: 0], dormantFallbackReaders)
        assertNamespaceWriteIsRejected(rejected, lastValue: 10, probe: probe, host: host)

        outerLeadingFits = false
        host.reload()
        host.render()
        XCTAssertEqual(try namespaceNode("primary", host: host).text, "12")
        XCTAssertFalse(namespaceContains("fallback", host: host))
        XCTAssertEqual(fallback.wrappedValue, 22)

        let outerBuildsBeforeResize = probe.outerBuilds
        let readerBuildsBeforeResize = probe.readerBuilds["outer", default: 0]
        host.runtime.setRootSize(IntSize(width: 640, height: 280))
        host.render()
        XCTAssertEqual(probe.outerBuilds, outerBuildsBeforeResize)
        XCTAssertGreaterThan(probe.readerBuilds["outer", default: 0], readerBuildsBeforeResize)
        XCTAssertEqual(try namespaceNode("primary", host: host).text, "12")
        XCTAssertEqual(fallback.wrappedValue, 22)

        primaryFits = false
        host.reload()
        host.render()
        XCTAssertFalse(namespaceContains("primary", host: host))
        XCTAssertEqual(try namespaceNode("fallback", host: host).text, "22")
        XCTAssertEqual(primary.wrappedValue, 12)
        assertNamespaceWriteIsRejected(rejected, lastValue: 10, probe: probe, host: host)
        XCTAssertEqual(try namespaceNode("fallback", host: host).text, "22")
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testInheritedNamespaceKeepsTabPageStateAcrossTabSelectionAndOuterDormancy() async throws {
        let probe = ViewThatFitsNamespaceProbe()
        let clock = RuntimeTestClock()
        var outerLeadingFits = false
        var selectedPage = "a"
        let selection = Binding<String>(get: { selectedPage }, set: { selectedPage = $0 })
        let host = MountedOnChangeTestHost {
            probe.outerBuilds += 1
            return AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.clear
                        .frame(width: outerLeadingFits ? 10 : 1_000, height: 20)
                        .accessibilityIdentifier("namespace.tab.outer.leading")
                    TabView(selection: selection) {
                        ViewThatFitsNamespaceCounter(name: "tab.a", seed: 30, probe: probe)
                            .tag("a").tabItem { Text("A") }
                        ViewThatFitsNamespaceCounter(name: "tab.b", seed: 50, probe: probe)
                            .tag("b").tabItem { Text("B") }
                    }
                    .frame(width: 240, height: 160)
                })
        }
        defer { host.close() }
        clock.now = host.runtime.clock()
        host.runtime.clock = { clock.now }
        host.render()
        let pageA = try probe.binding("tab.a")
        XCTAssertEqual(try namespaceNode("tab.a", host: host).text, "30")
        XCTAssertFalse(namespaceContains("tab.b", host: host))
        pageA.wrappedValue = 31
        host.render()
        XCTAssertEqual(try namespaceNode("tab.a", host: host).text, "31")

        let inactiveABuilds = probe.bodyBuilds["tab.a", default: 0]
        selection.wrappedValue = "b"
        host.reload()
        // The in-memory host does not tick animations when it renders. Finish
        // this tab transition explicitly so an outgoing overlay cannot retain A.
        clock.now += 1
        _ = host.runtime.tickAnimations(at: clock.now)
        host.render()
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertFalse(namespaceContains("tab.a", host: host))
        XCTAssertEqual(probe.bodyBuilds["tab.a", default: 0], inactiveABuilds)
        let pageB = try probe.binding("tab.b")
        XCTAssertEqual(try namespaceNode("tab.b", host: host).text, "50")
        XCTAssertEqual(pageA.wrappedValue, 31)
        pageB.wrappedValue = 51
        host.render()
        XCTAssertEqual(try namespaceNode("tab.b", host: host).text, "51")
        pageA.wrappedValue = 32
        host.render()
        XCTAssertEqual(pageA.wrappedValue, 32)
        XCTAssertEqual(try namespaceNode("tab.b", host: host).text, "51")
        XCTAssertEqual(probe.bodyBuilds["tab.a", default: 0], inactiveABuilds)

        let dormantBodies = probe.bodyBuilds
        outerLeadingFits = true
        host.reload()
        clock.now += 1
        _ = host.runtime.tickAnimations(at: clock.now)
        host.render()
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertTrue(namespaceContains("tab.outer.leading", host: host))
        XCTAssertFalse(namespaceContains("tab.a", host: host))
        XCTAssertFalse(namespaceContains("tab.b", host: host))
        XCTAssertEqual(probe.bodyBuilds, dormantBodies)
        pageA.wrappedValue = 33
        host.render()
        XCTAssertEqual(pageA.wrappedValue, 33)
        XCTAssertEqual(pageB.wrappedValue, 51)
        pageB.wrappedValue = 52
        host.render()
        XCTAssertEqual(pageA.wrappedValue, 33)
        XCTAssertEqual(pageB.wrappedValue, 52)
        XCTAssertEqual(probe.bodyBuilds, dormantBodies)
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)

        outerLeadingFits = false
        host.reload()
        clock.now += 1
        _ = host.runtime.tickAnimations(at: clock.now)
        host.render()
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(try namespaceNode("tab.b", host: host).text, "52")
        XCTAssertFalse(namespaceContains("tab.a", host: host))
        XCTAssertEqual(pageA.wrappedValue, 33)
        XCTAssertEqual(probe.bodyBuilds["tab.a", default: 0], dormantBodies["tab.a", default: 0])

        let inactiveBBuilds = probe.bodyBuilds["tab.b", default: 0]
        selection.wrappedValue = "a"
        host.reload()
        clock.now += 1
        _ = host.runtime.tickAnimations(at: clock.now)
        host.render()
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(try namespaceNode("tab.a", host: host).text, "33")
        XCTAssertFalse(namespaceContains("tab.b", host: host))
        XCTAssertEqual(pageA.wrappedValue, 33)
        XCTAssertEqual(pageB.wrappedValue, 52)
        XCTAssertEqual(probe.bodyBuilds["tab.b", default: 0], inactiveBBuilds)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }
}

@MainActor
private final class ViewThatFitsNamespaceProbe {
    var outerBuilds = 0
    var bodyBuilds: [String: Int] = [:]
    var readerBuilds: [String: Int] = [:]
    var bindings: [String: Binding<Int>] = [:]
    var zeroSlotOwner: StateMountOwner?

    func record(_ name: String, binding: Binding<Int>) {
        bodyBuilds[name, default: 0] += 1
        bindings[name] = binding
    }

    func recordReader(_ name: String) {
        readerBuilds[name, default: 0] += 1
    }

    func recordZeroSlotOwner() {
        bodyBuilds["zero", default: 0] += 1
        zeroSlotOwner = ViewBuildContextScope.current?.viewIdentity.installedOwner
    }

    func binding(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Binding<Int> {
        try XCTUnwrap(bindings[name], "Expected a binding for \(name)", file: file, line: line)
    }
}

// This owns one State slot while producing empty output. Native writer-route
// coverage belongs to the separate namespace protocol tests.
@MainActor
private struct ViewThatFitsNamespaceEmptyState: View {
    @State private var value: Int
    let probe: ViewThatFitsNamespaceProbe

    init(seed: Int, probe: ViewThatFitsNamespaceProbe) {
        _value = State(initialValue: seed)
        self.probe = probe
    }

    var body: some View {
        probe.record("empty", binding: $value)
        return EmptyView()
    }
}

// No DynamicProperty: this declaration must exist independently of slot count.
@MainActor
private struct ViewThatFitsNamespaceZeroSlotOwner: View {
    let probe: ViewThatFitsNamespaceProbe

    var body: some View {
        probe.recordZeroSlotOwner()
        return EmptyView()
    }
}

@MainActor
private struct ViewThatFitsNamespaceCounter: View {
    @State private var value: Int
    let name: String
    let probe: ViewThatFitsNamespaceProbe

    init(name: String, seed: Int, probe: ViewThatFitsNamespaceProbe) {
        _value = State(initialValue: seed)
        self.name = name
        self.probe = probe
    }

    var body: some View {
        probe.record(name, binding: $value)
        return Text(String(value)).accessibilityIdentifier("namespace.\(name)")
    }
}

@MainActor
private func assertNamespaceWriteIsRejected(
    _ binding: Binding<Int>, lastValue: Int, probe: ViewThatFitsNamespaceProbe,
    host: MountedOnChangeTestHost, file: StaticString = #filePath, line: UInt = #line
) {
    let before = probe.outerBuilds
    binding.wrappedValue = 99
    XCTAssertEqual(binding.wrappedValue, lastValue, file: file, line: line)
    XCTAssertEqual(probe.outerBuilds, before, file: file, line: line)
    host.render()
    XCTAssertEqual(binding.wrappedValue, lastValue, file: file, line: line)
    XCTAssertEqual(probe.outerBuilds, before, file: file, line: line)
}

@MainActor
private func namespaceContains(_ name: String, host: MountedOnChangeTestHost) -> Bool {
    namespaceDescendants(host.runtime.root).contains { $0.accessibilityIdentifier == "namespace.\(name)" }
}

@MainActor
private func namespaceNode(
    _ name: String, host: MountedOnChangeTestHost, file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    let matches = namespaceDescendants(host.runtime.root).filter {
        $0.accessibilityIdentifier == "namespace.\(name)"
    }
    XCTAssertEqual(matches.count, 1, file: file, line: line)
    return try XCTUnwrap(matches.first, file: file, line: line)
}

@MainActor
private func namespaceDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(namespaceDescendants)
}
