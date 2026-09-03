import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsRecursiveDeferredNamespaceTests: XCTestCase {
    func testLocalOuterReaderOmissionRevokesNestedReaderColdTabStateBeforeFreshReturn() async throws {
        let probe = RecursiveDeferredNamespaceProbe()
        let clock = RuntimeTestClock()
        var includeB = true
        var seed = 13
        var selectedPage = "a"
        let selection = Binding<String>(get: { selectedPage }, set: { selectedPage = $0 })
        let host = MountedOnChangeTestHost(size: Size(width: 600, height: 240)) {
            probe.rootBuilds += 1
            return AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: 1_200, height: 20)
                    GeometryReader { _ in
                        let _ = probe.recordReaderA()
                        if includeB {
                            GeometryReader { _ in
                                let _ = probe.recordReaderB()
                                TabView(selection: selection) {
                                    RecursiveDeferredNamespacePage(name: "a", seed: seed, probe: probe)
                                        .tag("a").tabItem { Text("A") }
                                    RecursiveDeferredNamespacePage(name: "b", seed: seed, probe: probe)
                                        .tag("b").tabItem { Text("B") }
                                }
                            }
                            .frame(width: 240, height: 160)
                        }
                    }
                })
        }
        defer { host.close() }
        clock.now = host.runtime.clock()
        host.runtime.clock = { clock.now }

        host.render()
        let oldA = try XCTUnwrap(probe.bindings["a"])
        XCTAssertEqual(oldA.wrappedValue, 13)
        XCTAssertEqual(try recursiveDeferredPage("a", in: host).text, "13")
        XCTAssertFalse(recursiveDeferredContainsPage("b", in: host))

        oldA.wrappedValue = 17
        host.render()
        XCTAssertEqual(oldA.wrappedValue, 17)
        XCTAssertEqual(try recursiveDeferredPage("a", in: host).text, "17")

        let coldABodyBuilds = probe.pageBodyBuilds["a", default: 0]
        selection.wrappedValue = "b"
        host.reload()
        // Reload starts the normal Tab crossfade. Rendering alone does not
        // tick it, so finish its fixed duration before asserting A is cold.
        clock.now += 1
        _ = host.runtime.tickAnimations(at: clock.now)
        host.render()
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertFalse(recursiveDeferredContainsPage("a", in: host))
        XCTAssertEqual(probe.pageBodyBuilds["a", default: 0], coldABodyBuilds)
        let oldB = try XCTUnwrap(probe.bindings["b"])
        XCTAssertEqual(oldB.wrappedValue, 13)
        XCTAssertEqual(try recursiveDeferredPage("b", in: host).text, "13")

        oldA.wrappedValue = 19
        host.render()
        XCTAssertEqual(oldA.wrappedValue, 19)
        XCTAssertEqual(oldB.wrappedValue, 13)
        XCTAssertFalse(recursiveDeferredContainsPage("a", in: host))
        XCTAssertEqual(probe.pageBodyBuilds["a", default: 0], coldABodyBuilds)
        XCTAssertEqual(try recursiveDeferredPage("b", in: host).text, "13")
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)

        // W is the host's only component, and its fallback is the unframed
        // reader A. Reader B belongs inside A, with no intervening ViewThatFits.
        XCTAssertEqual(host.runtime.root.children.count, 1)
        let w = try XCTUnwrap(host.runtime.root.children.first)
        XCTAssertEqual(w.selectedContentRole, .viewThatFits)
        XCTAssertEqual(w.children.count, 1)
        let a = try XCTUnwrap(w.children.first)
        XCTAssertTrue(a.parent === w)
        XCTAssertNotNil(a.geometryReaderBuild)
        let readersBeforeOmission = recursiveDeferredDescendants(w).filter { $0.geometryReaderBuild != nil }
        XCTAssertEqual(readersBeforeOmission.count, 2)
        XCTAssertTrue(readersBeforeOmission.contains { $0 === a })
        let rootBuildsBeforeLocal = probe.rootBuilds
        let aBuildsBeforeLocal = probe.readerABuilds
        let bBuildsBeforeLocal = probe.readerBBuilds
        let pagesBeforeLocal = probe.pageBodyBuilds

        includeB = false
        host.runtime.setRootSize(IntSize(width: 640, height: 240))
        host.render()
        XCTAssertEqual(probe.rootBuilds, rootBuildsBeforeLocal)
        XCTAssertGreaterThan(probe.readerABuilds, aBuildsBeforeLocal)
        XCTAssertEqual(probe.readerBBuilds, bBuildsBeforeLocal)
        XCTAssertEqual(probe.pageBodyBuilds, pagesBeforeLocal)
        XCTAssertTrue(host.runtime.root.children.first === w)
        XCTAssertTrue(w.children.first === a)
        let readersAfterOmission = recursiveDeferredDescendants(w).filter { $0.geometryReaderBuild != nil }
        XCTAssertEqual(readersAfterOmission.count, 1)
        XCTAssertTrue(readersAfterOmission.first === a)
        XCTAssertFalse(recursiveDeferredContainsPage("a", in: host))
        XCTAssertFalse(recursiveDeferredContainsPage("b", in: host))
        let aBuildsAfterOmission = probe.readerABuilds
        oldA.wrappedValue = 99
        oldB.wrappedValue = 99
        XCTAssertEqual(oldA.wrappedValue, 19)
        XCTAssertEqual(oldB.wrappedValue, 13)
        XCTAssertEqual(probe.rootBuilds, rootBuildsBeforeLocal)
        XCTAssertEqual(probe.readerABuilds, aBuildsAfterOmission)
        XCTAssertEqual(probe.readerBBuilds, bBuildsBeforeLocal)
        XCTAssertEqual(probe.pageBodyBuilds, pagesBeforeLocal)

        seed = 37
        includeB = true
        host.runtime.setRootSize(IntSize(width: 680, height: 240))
        host.render()
        XCTAssertEqual(probe.rootBuilds, rootBuildsBeforeLocal)
        XCTAssertGreaterThan(probe.readerABuilds, aBuildsAfterOmission)
        XCTAssertGreaterThan(probe.readerBBuilds, bBuildsBeforeLocal)
        XCTAssertEqual(probe.pageBodyBuilds["a", default: 0], coldABodyBuilds)
        XCTAssertTrue(host.runtime.root.children.first === w)
        XCTAssertTrue(w.children.first === a)
        let readersAfterReturn = recursiveDeferredDescendants(w).filter { $0.geometryReaderBuild != nil }
        XCTAssertEqual(readersAfterReturn.count, 2)
        XCTAssertTrue(readersAfterReturn.contains { $0 === a })
        XCTAssertFalse(recursiveDeferredContainsPage("a", in: host))
        let freshB = try XCTUnwrap(probe.bindings["b"])
        XCTAssertEqual(freshB.wrappedValue, 37)
        XCTAssertEqual(try recursiveDeferredPage("b", in: host).text, "37")
        XCTAssertEqual(oldA.wrappedValue, 19)
        XCTAssertEqual(oldB.wrappedValue, 13)

        freshB.wrappedValue = 41
        host.render()
        XCTAssertGreaterThan(probe.rootBuilds, rootBuildsBeforeLocal)
        XCTAssertEqual(freshB.wrappedValue, 41)
        XCTAssertEqual(try recursiveDeferredPage("b", in: host).text, "41")
        XCTAssertEqual(probe.pageBodyBuilds["a", default: 0], coldABodyBuilds)
        let rootBuildsAfterFreshWrite = probe.rootBuilds
        let pagesAfterFreshWrite = probe.pageBodyBuilds
        oldA.wrappedValue = 99
        XCTAssertEqual(oldA.wrappedValue, 19)
        XCTAssertEqual(oldB.wrappedValue, 13)
        XCTAssertEqual(freshB.wrappedValue, 41)
        XCTAssertEqual(probe.rootBuilds, rootBuildsAfterFreshWrite)
        XCTAssertEqual(probe.pageBodyBuilds, pagesAfterFreshWrite)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }
}

@MainActor
private final class RecursiveDeferredNamespaceProbe {
    var rootBuilds = 0
    var readerABuilds = 0
    var readerBBuilds = 0
    var pageBodyBuilds: [String: Int] = [:]
    var bindings: [String: Binding<Int>] = [:]

    func recordReaderA() { readerABuilds += 1 }
    func recordReaderB() { readerBBuilds += 1 }

    func recordPage(_ name: String, binding: Binding<Int>) {
        pageBodyBuilds[name, default: 0] += 1
        bindings[name] = binding
    }
}

@MainActor
private struct RecursiveDeferredNamespacePage: View {
    @State private var value: Int
    let name: String
    let probe: RecursiveDeferredNamespaceProbe

    init(name: String, seed: Int, probe: RecursiveDeferredNamespaceProbe) {
        _value = State(initialValue: seed)
        self.name = name
        self.probe = probe
    }

    var body: some View {
        probe.recordPage(name, binding: $value)
        return Text(String(value)).accessibilityIdentifier("recursive.page.\(name)")
    }
}

@MainActor
private func recursiveDeferredContainsPage(_ name: String, in host: MountedOnChangeTestHost) -> Bool {
    recursiveDeferredDescendants(host.runtime.root).contains { $0.accessibilityIdentifier == "recursive.page.\(name)" }
}

@MainActor
private func recursiveDeferredPage(
    _ name: String, in host: MountedOnChangeTestHost,
    file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    let matches = recursiveDeferredDescendants(host.runtime.root).filter {
        $0.accessibilityIdentifier == "recursive.page.\(name)"
    }
    XCTAssertEqual(matches.count, 1, file: file, line: line)
    return try XCTUnwrap(matches.first, file: file, line: line)
}

@MainActor
private func recursiveDeferredDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(recursiveDeferredDescendants)
}
