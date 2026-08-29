import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ProgressViewStyleConfigurationTests: XCTestCase {
    func testCustomStyleBuildsItsReturnedPublicViews() async throws {
        let probe = ProgressStyleTestProbe()
        let node = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.25) {
                Text("Source label")
            } currentValueLabel: {
                Text("Source value")
            }
            .progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "custom")))

        XCTAssertEqual(probe.calls, ["custom"])
        XCTAssertEqual(try XCTUnwrap(probe.configurations.first).fractionCompleted, 0.25)
        XCTAssertEqual(ProgressStyleTestSupport.texts(node), ["custom", "Source label", "Source value"])
        XCTAssertTrue(ProgressStyleTestSupport.progressNodes(node).isEmpty)
    }

    func testStyleRequirementSuppliesViewBuilderForConditionalAndOptionalContent() async {
        let probe = ProgressStyleTestProbe()
        let first = ProgressStyleTestSupport.makeNode(
            ProgressView("Label", value: 0.5)
                .progressViewStyle(ProgressStyleConditionalStyle(probe: probe, showsValue: true)))
        let second = ProgressStyleTestSupport.makeNode(
            ProgressView().progressViewStyle(ProgressStyleConditionalStyle(probe: probe, showsValue: false)))

        XCTAssertEqual(ProgressStyleTestSupport.texts(first), ["Determinate", "Label"])
        XCTAssertEqual(ProgressStyleTestSupport.texts(second), ["Waiting"])
        XCTAssertEqual(probe.calls, ["conditional", "conditional"])
    }

    func testConfigurationKeepsFiniteFractionsAndIndeterminateNilDistinct() async throws {
        let rows: [(Double?, Double, Double?)] = [
            (nil, 1, nil), (0, 1, 0), (0.5, 2, 0.25), (1, 1, 1),
            (-1, 2, 0), (3, 2, 1), (2, 0, 0), (2, -1, 0),
        ]
        for (value, total, expected) in rows {
            let probe = ProgressStyleTestProbe()
            _ = ProgressStyleTestSupport.makeNode(
                ProgressView(value: value, total: total)
                    .progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "fraction")))
            let configuration = try XCTUnwrap(probe.configurations.first)
            XCTAssertEqual(configuration.fractionCompleted, expected)
            XCTAssertEqual(configuration.retainedValue?.bitPattern, value?.bitPattern)
            XCTAssertEqual(configuration.retainedTotal.bitPattern, total.bitPattern)
        }
    }

    func testConfigurationDelegationKeepsTheOriginalPrimitiveNumericInputs() async throws {
        let value = 0.2
        let total = 3.0
        let probe = ProgressStyleTestProbe()
        _ = ProgressStyleTestSupport.makeNode(
            ProgressView(value: value, total: total)
                .progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "capture")))
        let configuration = try XCTUnwrap(probe.configurations.first)
        let ordinary = ProgressStyleTestSupport.makeNode(ProgressView(value: value, total: total))
        let delegated = ProgressStyleTestSupport.makeNode(ProgressView(configuration))

        XCTAssertEqual(configuration.retainedValue?.bitPattern, value.bitPattern)
        XCTAssertEqual(configuration.retainedTotal.bitPattern, total.bitPattern)
        XCTAssertEqual(
            delegated.children[1].frame.size.width.bitPattern, ordinary.children[1].frame.size.width.bitPattern)
        XCTAssertEqual(delegated.accessibilityValue, ordinary.accessibilityValue)
    }

    func testOnlyAuthoredLabelsArePresentInConfiguration() async throws {
        let probe = ProgressStyleTestProbe()
        _ = ProgressStyleTestSupport.makeNode(
            ProgressView().progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "none")))
        _ = ProgressStyleTestSupport.makeNode(
            ProgressView("Title").progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "title")))
        _ = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.5) {
                Text("Title")
            } currentValueLabel: {
                Text("Value")
            }
            .progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "both")))

        XCTAssertEqual(probe.configurations.count, 3)
        XCTAssertNil(probe.configurations[0].label)
        XCTAssertNil(probe.configurations[0].currentValueLabel)
        XCTAssertNotNil(probe.configurations[1].label)
        XCTAssertNil(probe.configurations[1].currentValueLabel)
        XCTAssertNotNil(probe.configurations[2].label)
        XCTAssertNotNil(probe.configurations[2].currentValueLabel)
    }

    func testMutableConfigurationCanRemoveEitherLabelWithoutRestoringOldArrays() async throws {
        let original = try ProgressStyleTestSupport.configuration(label: "Title", valueLabel: "Value")
        var withoutLabel = original
        withoutLabel.label = nil
        var withoutValue = original
        withoutValue.currentValueLabel = nil
        var withoutEither = withoutLabel
        withoutEither.currentValueLabel = nil

        XCTAssertEqual(
            ProgressStyleTestSupport.texts(ProgressStyleTestSupport.makeNode(ProgressView(withoutLabel))), ["Value"])
        XCTAssertEqual(
            ProgressStyleTestSupport.texts(ProgressStyleTestSupport.makeNode(ProgressView(withoutValue))), ["Title"])
        XCTAssertTrue(
            ProgressStyleTestSupport.texts(ProgressStyleTestSupport.makeNode(ProgressView(withoutEither))).isEmpty)
        XCTAssertEqual(
            ProgressStyleTestSupport.texts(ProgressStyleTestSupport.makeNode(ProgressView(original))),
            ["Title", "Value"])
    }

    func testMutableConfigurationCanReplaceTheTwoLabelRolesIndependently() async throws {
        let original = try ProgressStyleTestSupport.configuration(label: "First title", valueLabel: "First value")
        let replacement = try ProgressStyleTestSupport.configuration(label: "Second title", valueLabel: "Second value")
        var changedTitle = original
        changedTitle.label = replacement.label
        var changedValue = original
        changedValue.currentValueLabel = replacement.currentValueLabel

        XCTAssertEqual(
            ProgressStyleTestSupport.texts(ProgressStyleTestSupport.makeNode(ProgressView(changedTitle))),
            ["Second title", "First value"])
        XCTAssertEqual(
            ProgressStyleTestSupport.texts(ProgressStyleTestSupport.makeNode(ProgressView(changedValue))),
            ["First title", "Second value"])
        XCTAssertEqual(
            ProgressStyleTestSupport.texts(ProgressStyleTestSupport.makeNode(ProgressView(original))),
            ["First title", "First value"])
    }

    func testPublicBuiltInBodiesRenderWithoutReapplyingAnInheritedCustomStyle() async throws {
        let configuration = try ProgressStyleTestSupport.configuration(label: "Title", valueLabel: "Value")
        let probe = ProgressStyleTestProbe()
        let bodies = [
            AnyView(DefaultProgressViewStyle().makeBody(configuration: configuration)),
            AnyView(LinearProgressViewStyle().makeBody(configuration: configuration)),
            AnyView(CircularProgressViewStyle().makeBody(configuration: configuration)),
            AnyView(TimerProgressViewStyle().makeBody(configuration: configuration)),
        ]
        for body in bodies {
            let node = ProgressStyleTestSupport.makeNode(
                body.progressViewStyle(ProgressStyleDelegate(probe: probe, name: "must not recur")))
            XCTAssertEqual(ProgressStyleTestSupport.progressNodes(node).count, 1)
            XCTAssertEqual(ProgressStyleTestSupport.texts(node), ["Title", "Value"])
        }
        XCTAssertTrue(probe.calls.isEmpty)
    }

    func testLegacyProfilesConformToThePublicProtocolAndKeepBuiltInChrome() async {
        @MainActor
        func styled<Style: ProgressViewStyle>(_ style: Style) -> AnyView {
            AnyView(ProgressView(value: 0.5).progressViewStyle(style))
        }
        let profiles: [ProgressViewStyleProfile] = [.automatic, .linear, .circular, .timer]
        for (index, profile) in profiles.enumerated() {
            let node = ProgressStyleTestSupport.makeNode(styled(profile))
            XCTAssertEqual(node.children.count, index < 2 ? 2 : 12)
            XCTAssertEqual(node.accessibilityValue, "50%")
        }
        XCTAssertEqual(ProgressStyleTestSupport.makeNode(styled(.automatic)).children.count, 2)
        XCTAssertEqual(ProgressStyleTestSupport.makeNode(styled(.linear)).children.count, 2)
        XCTAssertEqual(ProgressStyleTestSupport.makeNode(styled(.circular)).children.count, 12)
        XCTAssertEqual(ProgressStyleTestSupport.makeNode(styled(.timer)).children.count, 12)
    }

    func testDelegatingStylePreservesDefaultAndExplicitAccessibilityValues() async throws {
        let probe = ProgressStyleTestProbe()
        let named = ProgressStyleTestSupport.makeNode(
            ProgressView("Loading", value: 0.4)
                .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "named")))
        let progress = try XCTUnwrap(ProgressStyleTestSupport.progressNodes(named).first)
        XCTAssertEqual(progress.accessibilityLabel, "Loading")
        XCTAssertEqual(progress.accessibilityValue, "40%")

        let explicit = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0.4)
                .progressViewStyle(ProgressStyleDelegate(probe: probe, name: "explicit"))
                .accessibilityLabel("Transfer")
                .accessibilityValue("Four of ten"))
        XCTAssertEqual(explicit.accessibilityLabel, "Transfer")
        XCTAssertEqual(explicit.accessibilityValue, "Four of ten")
        XCTAssertEqual(ProgressStyleTestSupport.progressNodes(explicit).count, 1)
    }

    func testIndeterminateCircularDelegationIsNotDeterminateZero() async {
        let probe = ProgressStyleTestProbe()
        let waiting = ProgressStyleTestSupport.makeNode(
            ProgressView().progressViewStyle(ProgressStyleDelegate(probe: probe, name: "waiting"))
                .progressViewStyle(.circular))
        let zero = ProgressStyleTestSupport.makeNode(
            ProgressView(value: 0).progressViewStyle(ProgressStyleDelegate(probe: probe, name: "zero"))
                .progressViewStyle(.circular))

        XCTAssertEqual(probe.calls, ["waiting", "zero"])
        XCTAssertEqual(waiting.children.count, 12)
        XCTAssertEqual(zero.children.count, 12)
        XCTAssertNil(waiting.accessibilityValue)
        XCTAssertEqual(zero.accessibilityValue, "0%")
        XCTAssertNotEqual(waiting.children[0].backgroundColor, zero.children[0].backgroundColor)
    }
}
@MainActor
final class ProgressStyleTestProbe {
    var calls: [String] = []
    var configurations: [ProgressViewStyleConfiguration] = []
}
@MainActor
struct ProgressStyleLabelStyle: ProgressViewStyle {
    let probe: ProgressStyleTestProbe
    let name: String

    func makeBody(configuration: Configuration) -> some View {
        let _ = probe.calls.append(name)
        let _ = probe.configurations.append(configuration)
        VStack {
            Text(name)
            configuration.label
            configuration.currentValueLabel
        }
    }
}
@MainActor
struct ProgressStyleDelegate: ProgressViewStyle {
    let probe: ProgressStyleTestProbe
    let name: String

    func makeBody(configuration: Configuration) -> some View {
        let _ = probe.calls.append(name)
        let _ = probe.configurations.append(configuration)
        ProgressView(configuration)
    }
}
@MainActor
private struct ProgressStyleConditionalStyle: ProgressViewStyle {
    let probe: ProgressStyleTestProbe
    let showsValue: Bool

    func makeBody(configuration: Configuration) -> some View {
        let _ = probe.calls.append("conditional")
        if showsValue {
            Text(configuration.fractionCompleted == nil ? "Indeterminate" : "Determinate")
        } else {
            Text("Waiting")
        }
        if let label = configuration.label { label }
    }
}
@MainActor
enum ProgressStyleTestSupport {
    static func makeNode<Content: View>(_ content: Content, environment: EnvironmentValues = EnvironmentValues())
        -> ViewNode
    {
        let runtime = RetainedViewRuntime()
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 640, height: 480) }, invalidateHandler: {})
            .withEnvironmentValues(environment)
        return makeViewComponent(content, context: context).makeNode(runtime: runtime)
    }

    static func nodes(_ root: ViewNode) -> [ViewNode] {
        [root] + root.children.flatMap { nodes($0) }
    }

    static func texts(_ root: ViewNode) -> [String] {
        nodes(root).compactMap(\.text).filter { !$0.isEmpty }
    }

    static func progressNodes(_ root: ViewNode) -> [ViewNode] {
        nodes(root).filter { $0.accessibilityTraits.contains(.isProgressIndicator) }
    }

    static func configuration(label: String, valueLabel: String) throws -> ProgressViewStyleConfiguration {
        let probe = ProgressStyleTestProbe()
        _ = makeNode(
            ProgressView(value: 0.4) {
                Text(label)
            } currentValueLabel: {
                Text(valueLabel)
            }
            .progressViewStyle(ProgressStyleLabelStyle(probe: probe, name: "configuration")))
        return try XCTUnwrap(probe.configurations.first)
    }
}
