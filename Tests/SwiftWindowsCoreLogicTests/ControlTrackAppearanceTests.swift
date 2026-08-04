import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// A slider's unfilled bar, a determinate `ProgressView`'s remainder, a
/// `Gauge`'s empty span and the body of an `off` switch are all the same
/// macOS role: a recessed groove a fill runs along. All four took their
/// colour from one hard-coded default on `Controls`
/// (`Color(red: 0.30, green: 0.34, blue: 0.40)`) and no WinSwiftUI caller
/// ever overrode it, so the groove was the *dark* appearance's slate in both
/// appearances. In a light-mode Form that drew a near-black bar across a
/// white settings pane, and an `off` switch came out charcoal — the last
/// controls that still looked like the dark app after `--appearance light`.
///
/// The role now lives on `ControlPalette.controlTrack`, so it resolves with
/// the appearance like every other control colour.
@MainActor
private func buildNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    configure: (ViewBuildContext) -> ViewBuildContext = { $0 }
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = configure(ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {}))
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func flatten(_ node: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = [node]
    for child in node.children {
        result.append(contentsOf: flatten(child))
    }
    return result
}

/// Every shade of a groove colour a control can paint: the flat fill, the
/// groove sheen both the slider and the switch use, and the deeper shade the
/// progress bar's recess uses.
private func grooveShades(of color: SwiftWindowsCore.Color) -> [SwiftWindowsCore.Color] {
    [
        color,
        Controls.shaded(color, by: Controls.grooveSheenFactor),
        Controls.shaded(color, by: 0.78),
    ]
}

final class ControlTrackAppearanceTests: XCTestCase {

    // MARK: - The role resolves with the appearance

    func testControlTrackDiffersBetweenAppearances() {
        XCTAssertNotEqual(
            ControlPalette.darkStandard.controlTrack,
            ControlPalette.lightStandard.controlTrack,
            "A groove that is one colour in both appearances is the dark appearance leaking into light")
    }

    /// The dark value is the historical literal, unchanged: this change is a
    /// light-mode fix and must not move a single dark-mode pixel (the gallery
    /// baselines are all rendered dark).
    func testDarkControlTrackIsUnchangedFromTheHistoricalLiteral() {
        let track = ControlPalette.darkStandard.controlTrack
        XCTAssertEqual(Double(track.red), 0.30, accuracy: 0.0005)
        XCTAssertEqual(Double(track.green), 0.34, accuracy: 0.0005)
        XCTAssertEqual(Double(track.blue), 0.40, accuracy: 0.0005)
        XCTAssertEqual(Double(track.alpha), 1.0, accuracy: 0.0005)
    }

    /// A groove on a white form has to read as recessed *and* stay light:
    /// darker than `controlBackground`, far lighter than the dark slate.
    func testLightControlTrackIsARecessedLightGrey() {
        let light = ControlPalette.lightStandard.controlTrack
        let dark = ControlPalette.darkStandard.controlTrack

        func luminance(_ c: SwiftWindowsCore.Color) -> Double {
            0.2126 * Double(c.red) + 0.7152 * Double(c.green) + 0.0722 * Double(c.blue)
        }

        XCTAssertGreaterThan(
            luminance(light), 0.75,
            "A light-mode groove sits close to the white surface it is cut into")
        XCTAssertLessThan(
            luminance(light), Double(ControlPalette.lightStandard.controlBackground.red),
            "…but darker than the control background, or it does not read as recessed")
        XCTAssertGreaterThan(
            luminance(light) - luminance(dark), 0.4,
            "The light groove is a different value from the dark one, not a nudge")
    }

    // MARK: - The controls are wired to it

    func testLightModeControlsPaintNoDarkModeGroove() async {
        await MainActor.run {
            let forbidden = grooveShades(of: ControlPalette.darkStandard.controlTrack)

            @MainActor func assertClean<V: View>(_ view: V, _ label: String) {
                let node = buildNode(view) { $0.withEnvironmentValue(\.colorScheme, .light) }
                for painted in flatten(node) {
                    guard let background = painted.backgroundColor else { continue }
                    XCTAssertFalse(
                        forbidden.contains(background),
                        "\(label) painted the dark appearance's groove in light mode: \(background)")
                }
            }

            assertClean(Slider(value: .constant(0.5)), "Slider")
            assertClean(ProgressView(value: 0.4, total: 1.0), "ProgressView")
            assertClean(Toggle("Sound", isOn: .constant(false)), "Toggle(off)")
            assertClean(Gauge(value: 0.4) { [AnyView(Text("Load"))] }, "Gauge")
        }
    }

    func testLightModeControlsPaintTheLightGroove() async {
        await MainActor.run {
            let expected = grooveShades(of: ControlPalette.lightStandard.controlTrack)

            @MainActor func assertPaints<V: View>(_ view: V, _ label: String) {
                let node = buildNode(view) { $0.withEnvironmentValue(\.colorScheme, .light) }
                let painted = flatten(node).compactMap { $0.backgroundColor }
                XCTAssertTrue(
                    painted.contains(where: { expected.contains($0) }),
                    "\(label) never painted the light appearance's groove")
            }

            assertPaints(Slider(value: .constant(0.5)), "Slider")
            assertPaints(ProgressView(value: 0.4, total: 1.0), "ProgressView")
            assertPaints(Toggle("Sound", isOn: .constant(false)), "Toggle(off)")
            assertPaints(Gauge(value: 0.4) { [AnyView(Text("Load"))] }, "Gauge")
        }
    }

    /// The mirror of the above: dark mode keeps painting the slate, so this
    /// is a light-mode fix and not a re-colouring of both appearances.
    func testDarkModeControlsStillPaintTheSlateGroove() async {
        await MainActor.run {
            let expected = grooveShades(of: ControlPalette.darkStandard.controlTrack)

            @MainActor func assertPaints<V: View>(_ view: V, _ label: String) {
                let node = buildNode(view) { $0.withEnvironmentValue(\.colorScheme, .dark) }
                let painted = flatten(node).compactMap { $0.backgroundColor }
                XCTAssertTrue(
                    painted.contains(where: { expected.contains($0) }),
                    "\(label) stopped painting the dark appearance's groove")
            }

            assertPaints(Slider(value: .constant(0.5)), "Slider")
            assertPaints(ProgressView(value: 0.4, total: 1.0), "ProgressView")
            assertPaints(Toggle("Sound", isOn: .constant(false)), "Toggle(off)")
        }
    }

    /// The slider's groove is structurally its first child, so this pins the
    /// wiring rather than the mere presence of a colour somewhere in a tree.
    func testSliderTrackNodeTakesItsColourFromThePalette() async {
        await MainActor.run {
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let palette = ControlPalette.resolve(colorScheme: scheme)
                let node = buildNode(Slider(value: .constant(0.5))) {
                    $0.withEnvironmentValue(\.colorScheme, scheme)
                }
                let track = node.children.first
                XCTAssertEqual(
                    track?.backgroundColor,
                    Controls.shaded(palette.controlTrack, by: Controls.grooveSheenFactor),
                    "The slider groove in \(scheme) is not the palette's control track")
            }
        }
    }
}
