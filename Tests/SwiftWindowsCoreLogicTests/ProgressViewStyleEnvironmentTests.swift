import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ProgressViewStyleEnvironmentTests: XCTestCase {
    func testInheritedStyleExecutesForEachProgressControlButNotOtherSiblings() async {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            VStack {
                ProgressView(value: 0.25)
                Text("Unstyled sibling")
                ProgressView(value: 0.75)
            }
            .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "inherited")))

        XCTAssertEqual(probe.calls, ["inherited", "inherited"])
        XCTAssertEqual(probe.configurations.map(\.fractionCompleted), [0.25, 0.75])
        XCTAssertEqual(ProgressStyleTestSupport.progressNodes(node).count, 2)
        XCTAssertEqual(ProgressStyleTestSupport.texts(node), ["Unstyled sibling"])
    }

    func testDelegationConsumesOnlyTheNearestInstallationAndRetainsTheInheritedChain() async {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.5)
                .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "inner"))
                .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "outer")))

        XCTAssertEqual(probe.calls, ["inner", "outer"])
        XCTAssertEqual(ProgressStyleTestSupport.progressNodes(node).count, 1)
        XCTAssertEqual(node.accessibilityValue, "50%")
    }

    func testThreeInstallationsOfTheSameStyleTypeRemainDistinct() async {
        let probe = ProgressStyleTestProbe()
        _ = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.5)
                .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "first"))
                .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "second"))
                .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "third")))

        XCTAssertEqual(probe.calls, ["first", "second", "third"])
    }

    func testLocalCustomOverrideDoesNotConsumeTheFollowingSiblingsStyle() async {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            VStack {
                ProgressView(value: 0.25)
                    .progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "replacement"))
                ProgressView(value: 0.75)
            }
            .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "outer")))

        XCTAssertEqual(probe.calls, ["replacement", "outer"])
        XCTAssertEqual(ProgressStyleTestSupport.progressNodes(node).count, 1)
        XCTAssertEqual(ProgressStyleTestSupport.progressNodes(node).first?.accessibilityValue, "75%")
        XCTAssertEqual(ProgressStyleTestSupport.texts(node), ["replacement"])
    }

    func testNewStyleInsideABodyIsScopedAndDoesNotReenterItsEnclosingStyle() async {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.5).progressViewStyle(ProgressStyleNestedBody(probe: probe)))

        XCTAssertEqual(probe.calls, ["body", "local"])
        XCTAssertEqual(ProgressStyleTestSupport.progressNodes(node).count, 2)
    }

    func testBuiltInOverrideDiscardsOlderCustomStylesOnlyWithinItsScope() async {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            VStack {
                ProgressView(value: 0.25).progressViewStyle(.circular)
                ProgressView(value: 0.75)
            }
            .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "outer")))
        let indicators = ProgressStyleTestSupport.progressNodes(node)

        XCTAssertEqual(probe.calls, ["outer"])
        XCTAssertEqual(indicators.count, 2)
        XCTAssertEqual(indicators[0].children.count, 12)
        XCTAssertEqual(indicators[1].children.count, 2)
    }

    func testDirectLegacyEnvironmentAssignmentOverridesCustomStyleEvenWhenEqual() async {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            VStack {
                ProgressView(value: 0.25).environment(\.progressViewStyle, .automatic)
                ProgressView(value: 0.5).environment(\.progressViewStyle, .circular)
                ProgressView(value: 0.75)
            }
            .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "outer")))
        let indicators = ProgressStyleTestSupport.progressNodes(node)

        XCTAssertEqual(probe.calls, ["outer"])
        XCTAssertEqual(indicators.count, 3)
        XCTAssertEqual(indicators.map { $0.children.count }, [2, 12, 2])
    }

    func testEnvironmentCopyAndTransformClearOnlyTheWrittenCustomInstallation() async {
        let probe = ProgressStyleTestProbe()
        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {})
            .withProgressViewStyle(ProgressStyleDelegate(probe: probe, name: "custom"))
        let original = context.environmentValues
        var copy = original
        copy.progressViewStyle = original.progressViewStyle
        XCTAssertNotNil(original.progressViewStyleInstallation)
        XCTAssertNil(copy.progressViewStyleInstallation)

        _ = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.5)
                .transformEnvironment(\.progressViewStyle) { $0 = .automatic },
            environment: original)
        XCTAssertTrue(probe.calls.isEmpty)
        _ = ProgressStyleTestSupport.makeNode(ProgressView(value: 0.5), environment: original)
        XCTAssertEqual(probe.calls, ["custom"])
    }

    func testLegacyProfileReaderKeepsBuiltinEqualityAndReportsCustomFallback() async {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            VStack {
                ProgressStyleProfileReader().progressViewStyle(.circular)
                ProgressStyleProfileReader().progressViewStyle(.linear)
                ProgressStyleProfileReader().progressViewStyle(.automatic)
                ProgressStyleProfileReader().progressViewStyle(
                    ProgressStyleDelegate(probe: probe, name: "not a control"))
            }
            .environment(\.progressViewStyle, .linear))

        XCTAssertEqual(ProgressStyleTestSupport.texts(node), ["CIRCULAR", "LINEAR", "AUTOMATIC", "LINEAR"])
        XCTAssertTrue(probe.calls.isEmpty)
    }

    func testCustomStyleReadsInheritedVisualEnvironmentThroughPublicWrappers() async throws {
        let snapshot = ProgressStyleEnvironmentSnapshot()
        _ = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.5)
                .progressViewStyle(ProgressStyleEnvironmentReader(snapshot: snapshot))
                .tint(.orange).font(.caption).controlSize(.large)
                .environment(\.colorScheme, .light).disabled(true))

        XCTAssertEqual(snapshot.tint, .orange)
        XCTAssertEqual(snapshot.font, .caption)
        XCTAssertEqual(snapshot.controlSize, .large)
        XCTAssertEqual(snapshot.colorScheme, .light)
        XCTAssertEqual(snapshot.isEnabled, false)
    }

    func testConfigurationLabelsResolveTheConsumingEnvironmentRatherThanTheCaptureEnvironment() async throws {
        let probe = ProgressStyleTestProbe()
        let captured = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.5) {
                ProgressStyleLabelEnvironmentReader(name: "label")
            } currentValueLabel: {
                ProgressStyleLabelEnvironmentReader(name: "value")
            }
            .progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "capture"))
            .environment(\.colorScheme, .dark).tint(.blue))
        let configuration = try XCTUnwrap(probe.configurations.first)
        XCTAssertEqual(ProgressStyleTestSupport.texts(captured), ["capture", "label|dark|blue", "value|dark|blue"])

        let wrappers = ProgressStyleTestSupport.makeNode(
            VStack {
                configuration.label
                configuration.currentValueLabel
            }
            .environment(\.colorScheme, .light).tint(.orange))
        let delegated = ProgressStyleTestSupport.makeNode(
            ProgressView(configuration).environment(\.colorScheme, .light).tint(.orange))

        XCTAssertEqual(ProgressStyleTestSupport.texts(wrappers), ["label|light|orange", "value|light|orange"])
        XCTAssertEqual(ProgressStyleTestSupport.texts(delegated), ["label|light|orange", "value|light|orange"])
    }

    func testLabelsHiddenStillAffectsAConfigurationDelegateWithoutDroppingTheConfigurationLabel() async throws {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            ProgressView("Hidden title", value: 0.5)
                .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "delegate"))
                .labelsHidden())

        XCTAssertNotNil(try XCTUnwrap(probe.configurations.first).label)
        XCTAssertTrue(ProgressStyleTestSupport.texts(node).isEmpty)
        XCTAssertEqual(node.accessibilityValue, "50%")
    }
}
@MainActor
private struct ProgressStyleNestedBody: ProgressViewStyle {
    let probe: ProgressStyleTestProbe

    func makeBody(configuration: Configuration) -> some View {
        let _ = probe.calls.append("body")
        VStack {
            ProgressView(configuration).progressViewStyle(ProgressStyleDelegate(probe: probe, name: "local"))
            ProgressView(configuration)
        }
    }
}
@MainActor
private struct ProgressStyleProfileReader: View {
    @Environment(\.progressViewStyle) private var profile

    var body: some View {
        Text(profile == .circular ? "CIRCULAR" : profile == .linear ? "LINEAR" : "AUTOMATIC")
    }
}
@MainActor
private final class ProgressStyleEnvironmentSnapshot {
    var tint: Color?
    var font: Font?
    var controlSize: ControlSize?
    var colorScheme: ColorScheme?
    var isEnabled: Bool?
}
@MainActor
private struct ProgressStyleEnvironmentReader: ProgressViewStyle {
    let snapshot: ProgressStyleEnvironmentSnapshot
    @Environment(\.tint) private var tint
    @Environment(\.font) private var font
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let _ = record()
        ProgressView(configuration)
    }

    private func record() {
        snapshot.tint = tint
        snapshot.font = font
        snapshot.controlSize = controlSize
        snapshot.colorScheme = colorScheme
        snapshot.isEnabled = isEnabled
    }
}
@MainActor
private struct ProgressStyleLabelEnvironmentReader: View {
    let name: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tint) private var tint

    var body: some View {
        Text("\(name)|\(colorScheme == .light ? "light" : "dark")|\(tint == .orange ? "orange" : "blue")")
    }
}
