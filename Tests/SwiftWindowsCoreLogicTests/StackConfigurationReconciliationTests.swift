import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Same-identity rebuilds must refresh native stack values without replacing
/// the installed stack or making an unchanged finite stack layout dirty.
@MainActor
final class StackConfigurationReconciliationTests: XCTestCase {
    func testVStackSpacingReloadPreservesInstalledNodes() async throws {
        try assertPublicSpacingReload(kind: .vertical)
    }

    func testHStackSpacingReloadPreservesInstalledNodes() async throws {
        try assertPublicSpacingReload(kind: .horizontal)
    }

    func testLazyVStackSpacingReloadPreservesInstalledNodes() async throws {
        try assertPublicSpacingReload(kind: .lazyVertical)
    }

    func testLazyHStackSpacingReloadPreservesInstalledNodes() async throws {
        try assertPublicSpacingReload(kind: .lazyHorizontal)
    }

    func testVStackAlignmentReloadPreservesInstalledNodes() async throws {
        try assertPublicAlignmentReload(kind: .vertical)
    }

    func testHStackAlignmentReloadPreservesInstalledNodes() async throws {
        try assertPublicAlignmentReload(kind: .horizontal)
    }

    func testLazyVStackAlignmentReloadPreservesInstalledNodes() async throws {
        try assertPublicAlignmentReload(kind: .lazyVertical)
    }

    func testLazyHStackAlignmentReloadPreservesInstalledNodes() async throws {
        try assertPublicAlignmentReload(kind: .lazyHorizontal)
    }

    func testVStackLeadingAlignmentRefreshesAfterLayoutDirectionChange() async throws {
        try assertPublicDirectionReload(kind: .vertical)
    }

    func testLazyVStackLeadingAlignmentRefreshesAfterLayoutDirectionChange() async throws {
        try assertPublicDirectionReload(kind: .lazyVertical)
    }

    func testPaddingInsetsReloadPreservesWrapperAndChild() async throws {
        let model = StackConfigurationPaddingModel()
        let host = makePublicHost {
            AnyView(
                stackConfigurationCell("child", width: 20, height: 10)
                    .padding(model.insets)
                    .accessibilityIdentifier("padding"))
        }
        defer { host.close() }
        let identifiers = ["padding", "child"]
        let installed = try identifiers.map { try publicNode($0, in: host) }
        try assertPublicFrame("padding", Rect(x: 0, y: 0, width: 20, height: 10), in: host, relativeTo: "padding")
        try assertPublicFrame("child", Rect(x: 0, y: 0, width: 20, height: 10), in: host, relativeTo: "padding")

        model.insets = EdgeInsets(top: 3, leading: 5, bottom: 7, trailing: 11)
        host.reload()
        host.render()

        try assertPublicFrame("padding", Rect(x: 0, y: 0, width: 36, height: 20), in: host, relativeTo: "padding")
        try assertPublicFrame("child", Rect(x: 5, y: 3, width: 20, height: 10), in: host, relativeTo: "padding")
        try assertPublicIdentity(identifiers, installed: installed, in: host)

        model.insets = .zero
        host.reload()
        host.render()

        try assertPublicFrame("padding", Rect(x: 0, y: 0, width: 20, height: 10), in: host, relativeTo: "padding")
        try assertPublicFrame("child", Rect(x: 0, y: 0, width: 20, height: 10), in: host, relativeTo: "padding")
        try assertPublicIdentity(identifiers, installed: installed, in: host)
    }

    func testHorizontalPaddingReloadPreservesWrapperAndChild() async throws {
        let model = StackConfigurationPaddingModel()
        let host = makePublicHost {
            AnyView(
                stackConfigurationCell("child", width: 20, height: 10)
                    .padding(.horizontal, model.horizontal)
                    .accessibilityIdentifier("padding"))
        }
        defer { host.close() }
        let identifiers = ["padding", "child"]
        let installed = try identifiers.map { try publicNode($0, in: host) }
        try assertPublicFrame("padding", Rect(x: 0, y: 0, width: 24, height: 10), in: host, relativeTo: "padding")
        try assertPublicFrame("child", Rect(x: 2, y: 0, width: 20, height: 10), in: host, relativeTo: "padding")

        model.horizontal = 9
        host.reload()
        host.render()

        try assertPublicFrame("padding", Rect(x: 0, y: 0, width: 38, height: 10), in: host, relativeTo: "padding")
        try assertPublicFrame("child", Rect(x: 9, y: 0, width: 20, height: 10), in: host, relativeTo: "padding")
        try assertPublicIdentity(identifiers, installed: installed, in: host)

        model.horizontal = 2
        host.reload()
        host.render()

        try assertPublicFrame("padding", Rect(x: 0, y: 0, width: 24, height: 10), in: host, relativeTo: "padding")
        try assertPublicFrame("child", Rect(x: 2, y: 0, width: 20, height: 10), in: host, relativeTo: "padding")
        try assertPublicIdentity(identifiers, installed: installed, in: host)
    }

    func testMountedStateSpacingInvalidationUpdatesExistingVStack() async throws {
        let capture = StackConfigurationStateCapture()
        let host = makePublicHost {
            AnyView(StackConfigurationStateView(seed: capture.nextSeed, capture: capture))
        }
        defer { host.close() }
        let identifiers = ["stack", "first", "second"]
        let installed = try identifiers.map { try publicNode($0, in: host) }
        let binding = try XCTUnwrap(capture.binding)
        let initialBuilds = capture.bodyBuilds
        XCTAssertEqual(binding.wrappedValue, 0)
        try assertPublicFrame("stack", Rect(x: 0, y: 0, width: 60, height: 40), in: host)
        try assertPublicFrame("second", Rect(x: 0, y: 20, width: 60, height: 20), in: host)

        // The installed projected binding must use the coordinator's ordinary
        // invalidation path. Do not manually reload for this State write.
        binding.wrappedValue = 12
        host.render()

        XCTAssertGreaterThan(capture.bodyBuilds, initialBuilds)
        XCTAssertEqual(try XCTUnwrap(capture.binding).wrappedValue, 12)
        try assertPublicFrame("stack", Rect(x: 0, y: 0, width: 60, height: 52), in: host)
        try assertPublicFrame("second", Rect(x: 0, y: 32, width: 60, height: 20), in: host)
        try assertPublicIdentity(identifiers, installed: installed, in: host)

        capture.nextSeed = 99
        host.reload()
        host.render()

        XCTAssertEqual(try XCTUnwrap(capture.binding).wrappedValue, 12)
        try assertPublicFrame("stack", Rect(x: 0, y: 0, width: 60, height: 52), in: host)
        try assertPublicFrame("second", Rect(x: 0, y: 32, width: 60, height: 20), in: host)
        try assertPublicIdentity(identifiers, installed: installed, in: host)
    }

    func testNativeMainAlignmentUpdatesBothStackVariants() async throws {
        for isLazy in [false, true] {
            for axis in [StackAxis.vertical, .horizontal] {
                let fixture = StackConfigurationNativeFixture(
                    axis: axis, isLazy: isLazy, extent: 100,
                    childSizes: [Size(width: 20, height: 20), Size(width: 20, height: 20)])
                defer { fixture.close() }
                let panel = try fixture.panel()
                let children = panel.children
                assertNativeTrack(panel, axis: axis, origins: [0, 20], extents: [20, 20])
                let cases: [(StackMainAlignment, [Double])] = [
                    (.center, [30, 50]), (.end, [60, 80]), (.start, [0, 20]),
                ]
                for (alignment, origins) in cases {
                    fixture.model.layout.mainAlignment = alignment
                    fixture.host.reload()
                    XCTAssertTrue(panel.subtreeDirtyFlags.contains(.layout))
                    fixture.render()
                    try assertNativeIdentity(fixture, panel: panel, children: children)
                    assertNativeTrack(panel, axis: axis, origins: origins, extents: [20, 20])
                }
            }
        }
    }

    func testNativeDistributionUpdatesBothStackVariants() async throws {
        for isLazy in [false, true] {
            for axis in [StackAxis.vertical, .horizontal] {
                let secondSize =
                    axis == .vertical ? Size(width: 20, height: 40) : Size(width: 40, height: 20)
                let fixture = StackConfigurationNativeFixture(
                    axis: axis, isLazy: isLazy, extent: 120,
                    childSizes: [Size(width: 20, height: 20), secondSize])
                defer { fixture.close() }
                let panel = try fixture.panel()
                let children = panel.children
                assertNativeTrack(panel, axis: axis, origins: [0, 20], extents: [20, 40])
                // The unequal ideals distinguish equal allocation from a
                // stored-enum-only update or a gap-placement-only update.
                let cases: [(StackDistribution, [Double], [Double])] = [
                    (.fillEqually, [0, 60], [60, 60]),
                    (.spaceBetween, [0, 80], [20, 40]),
                    (.spaceEvenly, [20, 60], [20, 40]),
                    (.fill, [0, 20], [20, 40]),
                ]
                for (distribution, origins, extents) in cases {
                    fixture.model.layout.distribution = distribution
                    fixture.host.reload()
                    XCTAssertTrue(panel.subtreeDirtyFlags.contains(.layout))
                    fixture.render()
                    try assertNativeIdentity(fixture, panel: panel, children: children)
                    assertNativeTrack(panel, axis: axis, origins: origins, extents: extents)
                }
            }
        }
    }

    func testNativeAxisChangesStillUseExistingCategoryCopy() async throws {
        for isLazy in [false, true] {
            let fixture = StackConfigurationNativeFixture(
                axis: .vertical, isLazy: isLazy, extent: 100,
                childSizes: [Size(width: 20, height: 20), Size(width: 20, height: 20)])
            defer { fixture.close() }
            let panel = try fixture.panel()
            let children = panel.children
            assertNativeTrack(panel, axis: .vertical, origins: [0, 20], extents: [20, 20])

            for axis in [StackAxis.horizontal, .vertical] {
                fixture.model.layout.axis = axis
                fixture.host.reload()
                XCTAssertTrue(panel.subtreeDirtyFlags.contains(.layout))
                fixture.render()
                try assertNativeIdentity(fixture, panel: panel, children: children)
                assertNativeTrack(panel, axis: axis, origins: [0, 20], extents: [20, 20])
            }
        }
    }

    func testNativeEagerLazyCategoryChangesPreserveExplicitIdentity() async throws {
        for axis in [StackAxis.vertical, .horizontal] {
            let fixture = StackConfigurationNativeFixture(
                axis: axis, isLazy: false, extent: 100,
                childSizes: [Size(width: 20, height: 20), Size(width: 20, height: 20)])
            defer { fixture.close() }
            let panel = try fixture.panel()
            let children = panel.children
            XCTAssertFalse(panel.layoutMode.virtualizesChildren)

            for isLazy in [true, false] {
                fixture.model.isLazy = isLazy
                fixture.host.reload()
                XCTAssertTrue(panel.subtreeDirtyFlags.contains(.layout))
                fixture.render()
                try assertNativeIdentity(fixture, panel: panel, children: children)
                assertNativeTrack(panel, axis: axis, origins: [0, 20], extents: [20, 20])
                XCTAssertEqual(panel.layoutMode.virtualizesChildren, isLazy)
            }
        }
    }

    func testEqualNativeConfigurationsLeaveBothStackVariantsClean() async throws {
        for isLazy in [false, true] {
            for axis in [StackAxis.vertical, .horizontal] {
                let layout = StackLayout(
                    axis: axis, spacing: 7,
                    padding: EdgeInsets(top: 2, leading: 3, bottom: 4, trailing: 5),
                    alignment: .center, mainAlignment: .end, distribution: .spaceEvenly)
                let fixture = StackConfigurationNativeFixture(
                    axis: axis, isLazy: isLazy, extent: 100, childSizes: [], initialLayout: layout)
                defer { fixture.close() }
                let panel = try fixture.panel()
                XCTAssertFalse(panel.hasDirtySubtree)

                fixture.host.reload()

                // A render here would clear evidence of an unconditional
                // layoutMode assignment, so inspect before any second render.
                XCTAssertFalse(panel.hasDirtySubtree)
                try assertNativeIdentity(fixture, panel: panel, children: [])
                XCTAssertEqual(panel.layoutMode.stackLayout, layout)
            }
        }
    }

    func testNativePaddingUpdatesBothStackVariants() async throws {
        for isLazy in [false, true] {
            for axis in [StackAxis.vertical, .horizontal] {
                let fixture = StackConfigurationNativeFixture(
                    axis: axis, isLazy: isLazy, extent: 120, childSizes: [Size(width: 20, height: 10)])
                defer { fixture.close() }
                let panel = try fixture.panel()
                let children = panel.children
                let child = try XCTUnwrap(children.first)
                assertRect(child.resolvedFrame, Rect(x: 0, y: 0, width: 20, height: 10))

                fixture.model.layout.padding = EdgeInsets(top: 3, leading: 5, bottom: 7, trailing: 11)
                fixture.host.reload()
                XCTAssertTrue(panel.subtreeDirtyFlags.contains(.layout))
                fixture.render()

                try assertNativeIdentity(fixture, panel: panel, children: children)
                assertRect(child.resolvedFrame, Rect(x: 5, y: 3, width: 20, height: 10))

                fixture.model.layout.padding = .zero
                fixture.host.reload()
                XCTAssertTrue(panel.subtreeDirtyFlags.contains(.layout))
                fixture.render()

                try assertNativeIdentity(fixture, panel: panel, children: children)
                assertRect(child.resolvedFrame, Rect(x: 0, y: 0, width: 20, height: 10))
            }
        }
    }

    func testUntaggedCategoryChangesContinueReplacingNodes() async throws {
        let cases: [(StackAxis, Bool, StackAxis, Bool)] = [
            (.vertical, false, .horizontal, false),
            (.vertical, true, .horizontal, true),
            (.vertical, false, .vertical, true),
            (.vertical, true, .vertical, false),
        ]
        for (oldAxis, oldLazy, newAxis, newLazy) in cases {
            let fixture = StackConfigurationNativeFixture(
                axis: oldAxis, isLazy: oldLazy, extent: 100,
                childSizes: [Size(width: 20, height: 20)], tag: nil)
            defer { fixture.close() }
            let original = try fixture.panel()
            XCTAssertNil(original.retainedViewIdentity)
            XCTAssertNil(original.nodeTag)

            fixture.model.layout.axis = newAxis
            fixture.model.isLazy = newLazy
            fixture.host.reload()
            fixture.render()

            let replacement = try fixture.panel()
            XCTAssertFalse(replacement === original)
            XCTAssertNil(replacement.retainedViewIdentity)
            XCTAssertNil(replacement.nodeTag)
            XCTAssertEqual(replacement.layoutMode.stackLayout, fixture.model.layout)
            XCTAssertEqual(replacement.layoutMode.virtualizesChildren, newLazy)
        }
    }

    private func assertPublicSpacingReload(
        kind: StackConfigurationPublicKind, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let model = StackConfigurationPublicModel()
        let host = makePublicHost { stackConfigurationView(kind: kind, model: model) }
        defer { host.close() }
        let identifiers = ["stack", "first", "second"]
        let installed = try identifiers.map { try publicNode($0, in: host, file: file, line: line) }
        try assertPublicSpacingGeometry(kind: kind, spacing: 0, host: host, file: file, line: line)

        for spacing in [12.0, 0.0] {
            model.spacing = spacing
            host.reload()
            host.render()
            try assertPublicSpacingGeometry(kind: kind, spacing: spacing, host: host, file: file, line: line)
            try assertPublicIdentity(identifiers, installed: installed, in: host, file: file, line: line)
        }
    }

    private func assertPublicSpacingGeometry(
        kind: StackConfigurationPublicKind, spacing: Double, host: MountedOnChangeTestHost,
        file: StaticString, line: UInt
    ) throws {
        let vertical = kind.axis == .vertical
        let panel = try publicNode("stack", in: host, file: file, line: line)
        let layout = try XCTUnwrap(panel.layoutMode.stackLayout, file: file, line: line)
        assertStackCase(panel.layoutMode, isLazy: kind.isLazy, file: file, line: line)
        XCTAssertEqual(layout.axis, kind.axis, file: file, line: line)
        XCTAssertEqual(layout.spacing, spacing, file: file, line: line)
        XCTAssertEqual(panel.layoutMode.virtualizesChildren, kind.isLazy, file: file, line: line)
        try assertPublicFrame(
            "stack", Rect(x: 0, y: 0, width: vertical ? 60 : 40 + spacing, height: vertical ? 40 + spacing : 60),
            in: host, file: file, line: line)
        try assertPublicFrame("first", Rect(x: 0, y: 0, width: 20, height: 20), in: host, file: file, line: line)
        try assertPublicFrame(
            "second",
            Rect(
                x: vertical ? 0 : 20 + spacing, y: vertical ? 20 + spacing : 0,
                width: vertical ? 60 : 20, height: vertical ? 20 : 60),
            in: host, file: file, line: line)
    }

    private func assertPublicAlignmentReload(
        kind: StackConfigurationPublicKind, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let model = StackConfigurationPublicModel()
        let host = makePublicHost { stackConfigurationView(kind: kind, model: model) }
        defer { host.close() }
        let identifiers = ["stack", "first", "second"]
        let installed = try identifiers.map { try publicNode($0, in: host, file: file, line: line) }
        try assertPublicCrossGeometry(kind: kind, offset: 0, alignment: .leading, host: host, file: file, line: line)

        model.horizontalAlignment = .trailing
        model.verticalAlignment = .bottom
        host.reload()
        host.render()

        try assertPublicCrossGeometry(kind: kind, offset: 40, alignment: .trailing, host: host, file: file, line: line)
        try assertPublicIdentity(identifiers, installed: installed, in: host, file: file, line: line)

        model.horizontalAlignment = .center
        model.verticalAlignment = .center
        host.reload()
        host.render()

        try assertPublicCrossGeometry(kind: kind, offset: 20, alignment: .center, host: host, file: file, line: line)
        try assertPublicIdentity(identifiers, installed: installed, in: host, file: file, line: line)
    }

    private func assertPublicDirectionReload(
        kind: StackConfigurationPublicKind, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let model = StackConfigurationPublicModel()
        let host = makePublicHost { stackConfigurationView(kind: kind, model: model) }
        defer { host.close() }
        let identifiers = ["stack", "first", "second"]
        let installed = try identifiers.map { try publicNode($0, in: host, file: file, line: line) }
        try assertPublicCrossGeometry(kind: kind, offset: 0, alignment: .leading, host: host, file: file, line: line)

        // The authored leading alignment never changes; the new environment
        // changes the physical cross alignment carried by StackLayout.
        model.layoutDirection = .rightToLeft
        host.reload()
        host.render()

        try assertPublicCrossGeometry(kind: kind, offset: 40, alignment: .trailing, host: host, file: file, line: line)
        try assertPublicIdentity(identifiers, installed: installed, in: host, file: file, line: line)

        model.layoutDirection = .leftToRight
        host.reload()
        host.render()

        try assertPublicCrossGeometry(kind: kind, offset: 0, alignment: .leading, host: host, file: file, line: line)
        try assertPublicIdentity(identifiers, installed: installed, in: host, file: file, line: line)
    }

    private func assertPublicCrossGeometry(
        kind: StackConfigurationPublicKind, offset: Double, alignment: StackCrossAlignment,
        host: MountedOnChangeTestHost, file: StaticString, line: UInt
    ) throws {
        let vertical = kind.axis == .vertical
        let panel = try publicNode("stack", in: host, file: file, line: line)
        let layout = try XCTUnwrap(panel.layoutMode.stackLayout, file: file, line: line)
        assertStackCase(panel.layoutMode, isLazy: kind.isLazy, file: file, line: line)
        XCTAssertEqual(layout.axis, kind.axis, file: file, line: line)
        XCTAssertEqual(layout.alignment, alignment, file: file, line: line)
        XCTAssertEqual(layout.spacing, 0, file: file, line: line)
        XCTAssertEqual(panel.layoutMode.virtualizesChildren, kind.isLazy, file: file, line: line)
        try assertPublicFrame(
            "stack", Rect(x: 0, y: 0, width: vertical ? 60 : 40, height: vertical ? 40 : 60),
            in: host, file: file, line: line)
        try assertPublicFrame(
            "first", Rect(x: vertical ? offset : 0, y: vertical ? 0 : offset, width: 20, height: 20),
            in: host, file: file, line: line)
        try assertPublicFrame(
            "second",
            Rect(
                x: vertical ? 0 : 20, y: vertical ? 20 : 0,
                width: vertical ? 60 : 20, height: vertical ? 20 : 60),
            in: host, file: file, line: line)
    }

    private func makePublicHost(
        content: @escaping @MainActor () -> AnyView
    ) -> MountedOnChangeTestHost {
        let host = MountedOnChangeTestHost(content: content)
        host.render()
        XCTAssertNil(host.coordinator.latestInstallationError)
        return host
    }

    private func publicNode(
        _ identifier: String, in host: MountedOnChangeTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        var matches: [ViewNode] = []
        var pending = [host.runtime.root]
        while let candidate = pending.popLast() {
            if candidate.accessibilityIdentifier == identifier { matches.append(candidate) }
            pending.append(contentsOf: candidate.children)
        }
        XCTAssertEqual(matches.count, 1, "Expected one node named \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, "Missing \(identifier)", file: file, line: line)
    }

    private func assertPublicIdentity(
        _ identifiers: [String], installed: [ViewNode], in host: MountedOnChangeTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(identifiers.count, installed.count, file: file, line: line)
        for (identifier, original) in zip(identifiers, installed) {
            XCTAssertTrue(
                try publicNode(identifier, in: host, file: file, line: line) === original,
                identifier, file: file, line: line)
        }
        XCTAssertNil(host.coordinator.latestInstallationError, file: file, line: line)
    }

    private func assertPublicFrame(
        _ identifier: String, _ expected: Rect, in host: MountedOnChangeTestHost,
        relativeTo reference: String = "stack", file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let target = try publicNode(identifier, in: host, file: file, line: line)
        let anchor = try publicNode(reference, in: host, file: file, line: line)
        let frame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: target), file: file, line: line)
        let anchorFrame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: anchor), file: file, line: line)
        let relative = Rect(
            x: frame.origin.x - anchorFrame.origin.x, y: frame.origin.y - anchorFrame.origin.y,
            width: frame.width, height: frame.height)
        assertRect(relative, expected, file: file, line: line)
    }

    private func assertNativeIdentity(
        _ fixture: StackConfigurationNativeFixture, panel: ViewNode, children: [ViewNode],
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertTrue(try fixture.panel(file: file, line: line) === panel, file: file, line: line)
        XCTAssertEqual(panel.children.count, children.count, file: file, line: line)
        for (current, original) in zip(panel.children, children) {
            XCTAssertTrue(current === original, file: file, line: line)
        }
        assertStackCase(panel.layoutMode, isLazy: fixture.model.isLazy, file: file, line: line)
        XCTAssertEqual(panel.layoutMode.stackLayout, fixture.model.layout, file: file, line: line)
        XCTAssertEqual(panel.layoutMode.virtualizesChildren, fixture.model.isLazy, file: file, line: line)
    }

    private func assertNativeTrack(
        _ panel: ViewNode, axis: StackAxis, origins: [Double], extents: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(panel.children.count, origins.count, file: file, line: line)
        XCTAssertEqual(origins.count, extents.count, file: file, line: line)
        for (child, expected) in zip(panel.children, zip(origins, extents)) {
            let frame = child.resolvedFrame
            let origin = axis == .vertical ? frame.minY : frame.minX
            let extent = axis == .vertical ? frame.height : frame.width
            let crossOrigin = axis == .vertical ? frame.minX : frame.minY
            let crossExtent = axis == .vertical ? frame.width : frame.height
            XCTAssertEqual(origin, expected.0, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(extent, expected.1, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(crossOrigin, 0, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(crossExtent, 20, accuracy: 0.0001, file: file, line: line)
        }
    }

    private func assertStackCase(
        _ mode: ViewLayoutMode, isLazy: Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
        if isLazy {
            guard case .lazyStack = mode else {
                XCTFail("Expected a lazy stack", file: file, line: line)
                return
            }
        } else {
            guard case .stack = mode else {
                XCTFail("Expected an eager stack", file: file, line: line)
                return
            }
        }
    }

    private func assertRect(_ actual: Rect, _ expected: Rect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
    }
}

fileprivate enum StackConfigurationPublicKind {
    case vertical
    case horizontal
    case lazyVertical
    case lazyHorizontal

    var axis: StackAxis {
        switch self {
        case .vertical, .lazyVertical: return .vertical
        case .horizontal, .lazyHorizontal: return .horizontal
        }
    }

    var isLazy: Bool {
        switch self {
        case .vertical, .horizontal: return false
        case .lazyVertical, .lazyHorizontal: return true
        }
    }
}

@MainActor
fileprivate final class StackConfigurationPublicModel {
    var spacing = 0.0
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .top
    var layoutDirection: LayoutDirection = .leftToRight
}

@MainActor
fileprivate final class StackConfigurationPaddingModel {
    var insets = EdgeInsets.zero
    var horizontal = 2.0
}

@MainActor
fileprivate func stackConfigurationCell(_ identifier: String, width: Double, height: Double) -> some View {
    Rectangle().frame(width: width, height: height).accessibilityIdentifier(identifier)
}

@MainActor
fileprivate func stackConfigurationView(
    kind: StackConfigurationPublicKind, model: StackConfigurationPublicModel
) -> AnyView {
    switch kind {
    case .vertical:
        return AnyView(
            VStack(alignment: model.horizontalAlignment, spacing: model.spacing) {
                stackConfigurationCell("first", width: 20, height: 20)
                stackConfigurationCell("second", width: 60, height: 20)
            }
            .environment(\.layoutDirection, model.layoutDirection)
            .accessibilityIdentifier("stack"))
    case .horizontal:
        return AnyView(
            HStack(alignment: model.verticalAlignment, spacing: model.spacing) {
                stackConfigurationCell("first", width: 20, height: 20)
                stackConfigurationCell("second", width: 20, height: 60)
            }
            .environment(\.layoutDirection, model.layoutDirection)
            .accessibilityIdentifier("stack"))
    case .lazyVertical:
        return AnyView(
            LazyVStack(alignment: model.horizontalAlignment, spacing: model.spacing) {
                stackConfigurationCell("first", width: 20, height: 20)
                stackConfigurationCell("second", width: 60, height: 20)
            }
            .environment(\.layoutDirection, model.layoutDirection)
            .accessibilityIdentifier("stack"))
    case .lazyHorizontal:
        return AnyView(
            LazyHStack(alignment: model.verticalAlignment, spacing: model.spacing) {
                stackConfigurationCell("first", width: 20, height: 20)
                stackConfigurationCell("second", width: 20, height: 60)
            }
            .environment(\.layoutDirection, model.layoutDirection)
            .accessibilityIdentifier("stack"))
    }
}

@MainActor
fileprivate final class StackConfigurationStateCapture {
    var nextSeed = 0.0
    var binding: Binding<Double>?
    var bodyBuilds = 0
}

@MainActor
fileprivate struct StackConfigurationStateView: View {
    @State private var spacing: Double
    let capture: StackConfigurationStateCapture

    init(seed: Double, capture: StackConfigurationStateCapture) {
        _spacing = State(wrappedValue: seed)
        self.capture = capture
    }

    var body: some View {
        capture.binding = $spacing
        capture.bodyBuilds += 1
        return VStack(alignment: .leading, spacing: spacing) {
            stackConfigurationCell("first", width: 20, height: 20)
            stackConfigurationCell("second", width: 60, height: 20)
        }
        .accessibilityIdentifier("stack")
    }
}

@MainActor
fileprivate final class StackConfigurationNativeModel {
    var layout: StackLayout
    var isLazy: Bool
    let extent: Double
    let childSizes: [Size]
    let tag: String?

    init(layout: StackLayout, isLazy: Bool, extent: Double, childSizes: [Size], tag: String?) {
        self.layout = layout
        self.isLazy = isLazy
        self.extent = extent
        self.childSizes = childSizes
        self.tag = tag
    }
}

@MainActor
fileprivate final class StackConfigurationNativeFixture {
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let model: StackConfigurationNativeModel

    init(
        axis: StackAxis, isLazy: Bool, extent: Double, childSizes: [Size],
        tag: String? = "native-stack", initialLayout: StackLayout? = nil
    ) {
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: extent, height: extent)))
        let host = ComponentHost(runtime: runtime)
        let model = StackConfigurationNativeModel(
            layout: initialLayout ?? StackLayout(axis: axis, alignment: .leading),
            isLazy: isLazy, extent: extent, childSizes: childSizes, tag: tag)
        self.runtime = runtime
        self.host = host
        self.model = model
        host.setContent {
            Component { _ in
                let children = model.childSizes.enumerated().map { index, size in
                    let child = ViewNode(preferredSize: size)
                    child.nodeTag = "native-child-\(index)"
                    return child
                }
                let panel = Controls.stackPanel(
                    frame: Rect(x: 0, y: 0, width: model.extent, height: model.extent),
                    stackLayout: model.layout, isHitTestVisible: false, children: children)
                if model.isLazy { panel.layoutMode = .lazyStack(model.layout) }
                panel.nodeTag = model.tag
                return panel
            }
        }
        _ = runtime.renderScene()
    }

    func panel(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        XCTAssertEqual(runtime.root.children.count, 1, file: file, line: line)
        return try XCTUnwrap(runtime.root.children.first, file: file, line: line)
    }

    func render() {
        _ = runtime.renderScene()
    }

    func close() {
        runtime.stopRenderLifecycleCallbacks()
        host.setComponents { [] }
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}
