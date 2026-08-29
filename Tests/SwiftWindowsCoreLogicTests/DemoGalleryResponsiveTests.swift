import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The public gallery is a real product surface, not a contact sheet: its
/// examples, navigation, appearance, and accessibility must survive the same
/// minimum-window contract as the existing dashboard.
@MainActor
final class DemoGalleryResponsiveTests: XCTestCase {
    private func snapshot(
        model: DemoDashboardModel,
        size: IntSize = IntSize(width: 1280, height: 720),
        colorScheme: ColorScheme = .dark,
        displayScale: Double = 1
    ) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            size: size,
            displayScale: displayScale,
            colorScheme: colorScheme
        )
    }

    private func galleryModel() -> DemoDashboardModel {
        let model = DemoDashboardModel()
        model.selectedScreen = .gallery
        return model
    }

    private func firstNode(
        in root: ViewNode,
        matching predicate: (ViewNode) -> Bool
    ) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if predicate(node) {
                return node
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    private func allNodes(
        in root: ViewNode,
        matching predicate: (ViewNode) -> Bool
    ) -> [ViewNode] {
        var matches: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            if predicate(node) {
                matches.append(node)
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return matches
    }

    private func textNode(in root: ViewNode, _ text: String) -> ViewNode? {
        firstNode(in: root) { $0.text?.caseInsensitiveCompare(text) == .orderedSame }
    }

    private func absoluteX(of node: ViewNode) -> Double {
        var position = 0.0
        var current: ViewNode? = node
        while let ancestor = current {
            position += ancestor.resolvedFrame.origin.x
            current = ancestor.parent
        }
        return position
    }

    private func absoluteY(of node: ViewNode) -> Double {
        var position = 0.0
        var current: ViewNode? = node
        while let ancestor = current {
            position += ancestor.resolvedFrame.origin.y
            current = ancestor.parent
        }
        return position
    }

    private func scrollReadiness(
        in runtime: RetainedViewRuntime, scroller: ViewNode
    ) -> String {
        return "layoutComplete=\(runtime.hasCompletedLayout) pending=\(runtime.hasPendingLayout)"
            + " inProgress=\(runtime.isLayoutInProgress) scrollerCached=\(scroller.cachedLayoutKey != nil)"
            + " scrollerPending=\(scroller.pendingLayoutKey != nil) content=\(scroller.resolvedContentSize)"
    }

    /// Layout callbacks may legitimately publish geometry that needs another
    /// pass after the snapshot's scene/frame pair. Bound convergence so a
    /// repeating invalidation still fails rather than hiding behind retries.
    private func settlePendingLayout(
        in runtime: RetainedViewRuntime,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<3 where runtime.hasPendingLayout {
            _ = runtime.renderScene(at: 0)
        }
        XCTAssertFalse(
            runtime.hasPendingLayout,
            "\(context): layout did not settle within three extra passes",
            file: file, line: line)
    }

    /// Inspect the actual native glyph cells emitted for a text leaf, after
    /// scrolling and clipping. Layout frames alone cannot detect text painted
    /// over an adjacent label. These gallery labels have no rotation or
    /// compositing group, so their cached ranges refer directly to this scene.
    private func paintedTextBounds(
        of node: ViewNode,
        in scene: GPUIScene,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Rect {
        let range = try XCTUnwrap(node.cachedScenePaintRange, file: file, line: line)
        XCTAssertGreaterThanOrEqual(range.lowerBound, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(range.upperBound, scene.paintRecords.count, file: file, line: line)
        guard range.lowerBound >= 0, range.upperBound <= scene.paintRecords.count else {
            return .zero
        }

        var bounds: Rect?
        for record in scene.paintRecords[range] {
            guard case .primitive(let layerIndex, let kind, let index) = record,
                case .glyph(let glyph)? = scene.primitive(kind: kind, inLayer: layerIndex, at: index)
            else { continue }

            XCTAssertEqual(glyph.rotationRadians, 0, file: file, line: line)
            let cell = Rect(
                x: Double(glyph.screenX), y: Double(glyph.screenY),
                width: Double(glyph.screenW), height: Double(glyph.screenH))
            let clip = Rect(
                x: Double(glyph.clipX), y: Double(glyph.clipY),
                width: Double(glyph.clipWidth), height: Double(glyph.clipHeight))
            guard glyph.colorA > 0, let visible = cell.intersected(with: clip) else { continue }

            if let previous = bounds {
                let left = min(previous.minX, visible.minX)
                let top = min(previous.minY, visible.minY)
                bounds = Rect(
                    x: left, y: top,
                    width: max(previous.maxX, visible.maxX) - left,
                    height: max(previous.maxY, visible.maxY) - top)
            } else {
                bounds = visible
            }
        }

        return try XCTUnwrap(
            bounds, "\(node.text ?? "text") must emit visible native glyphs", file: file, line: line)
    }

    private func activatingNode(in root: ViewNode, label: String) -> ViewNode? {
        if let labeled = firstNode(
            in: root,
            matching: {
                $0.accessibilityLabel == label && $0.onActivate != nil
            })
        {
            return labeled
        }

        var candidate = textNode(in: root, label)
        while let current = candidate {
            if current.onActivate != nil {
                return current
            }
            candidate = current.parent
        }
        return nil
    }

    private func relativeLuminance(of color: Color) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(Double(color.red))
            + 0.7152 * linear(Double(color.green))
            + 0.0722 * linear(Double(color.blue))
    }

    private func contrastRatio(text: Color, over background: Color) -> Double {
        let alpha = Double(text.alpha)
        let foreground = Color(
            red: Float(alpha * Double(text.red) + (1 - alpha) * Double(background.red)),
            green: Float(alpha * Double(text.green) + (1 - alpha) * Double(background.green)),
            blue: Float(alpha * Double(text.blue) + (1 - alpha) * Double(background.blue)),
            alpha: 1
        )
        let foregroundLuminance = relativeLuminance(of: foreground)
        let backgroundLuminance = relativeLuminance(of: background)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    func testGalleryRetainsMeaningfulSectionsAcrossSupportedWindowSizes() async {
        for size in [
            IntSize(width: 640, height: 480),
            IntSize(width: 800, height: 600),
            IntSize(width: 1280, height: 720),
        ] {
            let result = snapshot(model: galleryModel(), size: size)
            let root = result.runtime.root

            XCTAssertGreaterThan(result.scene.primitiveCount, 0)
            XCTAssertNotNil(textNode(in: root, "Component gallery"), "\(size): gallery heading")
            XCTAssertNotNil(textNode(in: root, "Input & controls"), "\(size): interactive controls")
            XCTAssertNotNil(textNode(in: root, "Visual rendering"), "\(size): rendering section")
            XCTAssertNotNil(
                textNode(in: root, "Presentation & navigation"),
                "\(size): presentation section remains reachable by scrolling"
            )
        }
    }

    func testMinimumWindowKeepsGalleryNavigationInsideViewport() async {
        let size = IntSize(width: 640, height: 480)
        let root = snapshot(model: galleryModel(), size: size).runtime.root

        guard
            let heading = textNode(in: root, "Component gallery"),
            let search = firstNode(
                in: root,
                matching: {
                    $0.accessibilityLabel == "Search components" && $0.isFocusable
                })
        else {
            return XCTFail("the minimum window needs both a gallery heading and an editable search field")
        }

        XCTAssertLessThan(absoluteY(of: heading), Double(size.height))
        XCTAssertLessThan(absoluteY(of: search), Double(size.height))

        for category in DemoGalleryCategory.allCases {
            let label = "Show \(category.label) examples"
            guard let button = activatingNode(in: root, label: label) else {
                return XCTFail("a 640pt gallery lost its \(category.label) category")
            }

            XCTAssertGreaterThanOrEqual(absoluteX(of: button), -0.5, "\(label): leading edge")
            XCTAssertLessThanOrEqual(
                absoluteX(of: button) + button.resolvedFrame.size.width,
                Double(size.width) + 0.5,
                "\(label): category controls must fit without horizontal clipping"
            )
            XCTAssertLessThan(absoluteY(of: button), Double(size.height), "\(label): visible above the fold")
        }
    }

    func testVisibleGalleryLabelsAreNotCrushedAtResponsiveBreakpoints() async {
        for size in [
            IntSize(width: 640, height: 480),
            IntSize(width: 780, height: 600),
            IntSize(width: 800, height: 600),
            IntSize(width: 1280, height: 720),
        ] {
            let root = snapshot(model: galleryModel(), size: size).runtime.root
            let crushed = allNodes(in: root) { node in
                guard let text = node.text, !text.isEmpty else { return false }
                let height = node.resolvedFrame.size.height
                let y = absoluteY(of: node)
                return height > 0 && height < 8 && y >= 0 && y < Double(size.height)
            }

            XCTAssertTrue(
                crushed.isEmpty,
                "\(size): visible labels shrank below their glyphs: \(crushed.compactMap(\.text))"
            )
        }
    }

    func testDesktopGalleryContainsRenderingAndPresentationExamples() async {
        let model = galleryModel()
        let root = snapshot(model: model).runtime.root

        for title in [
            "Actions & feedback",
            "Text entry & validation",
            "Selection & preferences",
            "Ranges & progress",
            "Status & inspection",
        ] {
            XCTAssertNotNil(textNode(in: root, title), "the live component workbench should contain \(title)")
        }

        for title in ["Gradient lab", "Glass & materials", "Motion studio", "Type & color", "Bitmap images"] {
            XCTAssertNotNil(textNode(in: root, title), "the rendering showcase should contain \(title)")
        }

        for title in ["Open Sheet", "Show Popover", "Show Alert", "Confirm Action", "Quick Actions"] {
            XCTAssertNotNil(
                activatingNode(in: root, label: title),
                "\(title) should be a real, activatable example rather than inert gallery chrome"
            )
        }

        guard let runAction = activatingNode(in: root, label: "Run action") else {
            return XCTFail("the control workbench needs a real primary example action")
        }

        let previousInteractionCount = model.interactionCount
        runAction.onActivate?()
        XCTAssertEqual(model.interactionCount, previousInteractionCount + 1)
        XCTAssertEqual(model.lastAction, "Ran component gallery action")
    }

    func testGalleryUsesAppearanceSpecificSurfacesAndReadableHeadings() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let root = snapshot(model: galleryModel(), colorScheme: scheme).runtime.root
            let palette = DemoPalette(colorScheme: scheme)

            XCTAssertNotNil(
                firstNode(in: root) {
                    ($0.backgroundColor == palette.base || $0.backgroundColor == palette.surface0)
                        && $0.resolvedFrame.size.width >= 600
                },
                "\(scheme): gallery page should inherit its semantic appearance"
            )

            guard let heading = textNode(in: root, "Component gallery") else {
                return XCTFail("\(scheme): expected the gallery heading")
            }

            XCTAssertGreaterThanOrEqual(
                contrastRatio(text: heading.textStyle.color, over: palette.base),
                4.5,
                "\(scheme): gallery heading needs readable semantic contrast"
            )
        }
    }

    func testGallerySearchFieldIsFocusableAndWritesSharedQuery() async {
        let model = galleryModel()
        let root = snapshot(model: model).runtime.root

        guard
            let search = firstNode(
                in: root,
                matching: {
                    $0.accessibilityLabel == "Search components" && $0.isFocusable
                })
        else {
            return XCTFail("gallery search must expose an editable keyboard-focusable field")
        }

        XCTAssertTrue(search.isHitTestVisible)
        search.onKeyDown?(KeyboardEvent(keyCode: 0x47))
        XCTAssertEqual(model.galleryQuery, "g", "typing should update the model-owned gallery query")
    }

    func testCategoryButtonsAreFocusableAndSwitchDisplayedSections() async {
        XCTAssertTrue(DemoGalleryCategory.controls.matches(query: "TOGGLE"))
        XCTAssertTrue(DemoGalleryCategory.visuals.matches(query: "  BLUR   gradient "))
        XCTAssertTrue(DemoGalleryCategory.presentations.matches(query: "sheet"))
        XCTAssertFalse(DemoGalleryCategory.controls.matches(query: "gradient"))
        XCTAssertFalse(DemoGalleryCategory.visuals.matches(query: "sheet"))

        let model = galleryModel()
        let initial = snapshot(model: model).runtime.root

        for category in DemoGalleryCategory.allCases {
            let label = "Show \(category.label) examples"
            guard let button = activatingNode(in: initial, label: label) else {
                return XCTFail("\(category.label) needs an actual category button")
            }
            XCTAssertTrue(button.isFocusable, "\(label) must be available to keyboard navigation")
            XCTAssertTrue(button.isHitTestVisible)
        }

        activatingNode(in: initial, label: "Show Rendering examples")?.onActivate?()
        XCTAssertEqual(model.selectedGalleryCategory, .visuals)

        let filtered = snapshot(model: model).runtime.root
        XCTAssertNotNil(textNode(in: filtered, "Visual rendering"))
        XCTAssertNil(
            textNode(in: filtered, "Presentation & navigation"),
            "selecting Rendering should remove unrelated presentation examples"
        )
    }

    func testUnmatchedSearchOffersRecoveryAndRestoresEveryCategory() async {
        let model = galleryModel()
        model.selectedGalleryCategory = .visuals
        model.galleryQuery = "no gallery example could match this phrase"

        let filtered = snapshot(model: model).runtime.root
        XCTAssertNotNil(textNode(in: filtered, "No matching examples"))

        guard let clear = activatingNode(in: filtered, label: "Clear search") else {
            return XCTFail("an unmatched query needs a real clear-search action")
        }

        clear.onActivate?()
        XCTAssertEqual(model.galleryQuery, "")
        XCTAssertEqual(model.selectedGalleryCategory, .all)

        let restored = snapshot(model: model).runtime.root
        XCTAssertNotNil(textNode(in: restored, "Input & controls"))
        XCTAssertNotNil(textNode(in: restored, "Visual rendering"))
        XCTAssertNotNil(textNode(in: restored, "Presentation & navigation"))
    }

    func testGalleryAccessibilityProjectionExposesNamedEditableAndButtons() async {
        let model = galleryModel()
        let root = snapshot(model: model).runtime.root

        guard let elements = AccessibilityProjection.project(root: root)?.flattened() else {
            return XCTFail("the gallery should project a real assistive-technology element tree")
        }

        let search = elements.first { $0.name == "Search components" }
        XCTAssertEqual(search?.controlType, .edit)
        XCTAssertEqual(search?.isEnabled, true)

        let intensity = elements.first { $0.name == "Render intensity" && $0.controlType == .slider }
        XCTAssertEqual(intensity?.controlType, .slider)
        XCTAssertEqual(intensity?.isEnabled, true)

        let capacity = elements.first { $0.name == "Pipeline capacity" && $0.controlType == .progressBar }
        XCTAssertEqual(capacity?.value, "62 percent reserved")

        for category in DemoGalleryCategory.allCases {
            let label = "Show \(category.label) examples"
            let button = elements.first { $0.name == label }
            XCTAssertEqual(button?.controlType, .button, "\(label) should announce a button role")
            XCTAssertEqual(button?.isEnabled, true)
        }
    }

    func testGalleryInheritsGlobalDynamicTypeSettings() async {
        let model = galleryModel()

        guard let baseline = textNode(in: snapshot(model: model).runtime.root, "Component gallery") else {
            return XCTFail("expected the default-size gallery heading")
        }
        let baselineSize = baseline.textStyle.nativeFontSize ?? 0

        model.fontScale = 1.4
        guard let enlarged = textNode(in: snapshot(model: model).runtime.root, "Component gallery") else {
            return XCTFail("expected the enlarged gallery heading")
        }

        XCTAssertGreaterThan(baselineSize, 0)
        XCTAssertGreaterThan(
            enlarged.textStyle.nativeFontSize ?? 0,
            baselineSize,
            "gallery type should follow the same global accessibility preference as every other screen"
        )
    }

    func testScrolledTypographyKeepsAdjacentLargeTextRunsSeparateAtFractionalScales() async throws {
        for scale in [1.25, 1.5] {
            let model = galleryModel()
            model.fontScale = 1.4
            model.animationsEnabled = false
            let result = snapshot(
                model: model, size: IntSize(width: 640, height: 480), displayScale: scale)
            settlePendingLayout(in: result.runtime, context: "typography \(scale)x")
            let root = result.runtime.root
            let title = try XCTUnwrap(textNode(in: root, "Type & color"))
            let subtitle = try XCTUnwrap(textNode(in: root, "Optical text sizes and semantic accents"))
            let sampleTitle = try XCTUnwrap(textNode(in: root, "Variable UI"))
            let sampleCaption = try XCTUnwrap(textNode(in: root, "13pt regular · 14pt semibold"))
            let scroller = try XCTUnwrap(firstNode(in: root) { $0.scrollAxis == .vertical })

            XCTAssertTrue(
                result.runtime.scrollToDescendant(title, anchorY: 0),
                scrollReadiness(in: result.runtime, scroller: scroller))
            let scene = result.runtime.renderScene(at: 0)
            XCTAssertGreaterThan(scroller.scrollOffset, 0, "the typography example must be reached by scrolling")

            let titleBounds = try paintedTextBounds(of: title, in: scene)
            let subtitleBounds = try paintedTextBounds(of: subtitle, in: scene)
            let sampleTitleBounds = try paintedTextBounds(of: sampleTitle, in: scene)
            let sampleCaptionBounds = try paintedTextBounds(of: sampleCaption, in: scene)

            XCTAssertLessThanOrEqual(
                titleBounds.maxY, subtitleBounds.minY,
                "\(scale)x: the enlarged card heading must not paint over its subtitle")
            XCTAssertLessThanOrEqual(
                subtitleBounds.maxY, sampleTitleBounds.minY,
                "\(scale)x: the type sample must remain below the card header")
            XCTAssertLessThanOrEqual(
                sampleTitleBounds.maxY, sampleCaptionBounds.minY,
                "\(scale)x: the sample's body and caption must remain separate painted lines")
        }
    }

    func testScrolledInvalidInputKeepsLargeValidationTextSeparateAtTheColumnBreakpoint() async throws {
        for width in [640, 780] {
            let model = galleryModel()
            model.fontScale = 1.4
            model.animationsEnabled = false
            model.galleryState.draftName = ""
            let result = snapshot(
                model: model, size: IntSize(width: Int32(width), height: 480), displayScale: 1.25)
            settlePendingLayout(in: result.runtime, context: "input \(width)pt")
            let root = result.runtime.root
            let section = try XCTUnwrap(
                firstNode(in: root) { $0.accessibilityIdentifier == "gallery.section.input" })
            let title = try XCTUnwrap(textNode(in: section, "Text entry & validation"))
            let detail = try XCTUnwrap(textNode(in: section, "Focusable input, submit handling, and live validation"))
            let validation = try XCTUnwrap(textNode(in: section, "Enter 1–36 nonblank characters"))
            let count = try XCTUnwrap(textNode(in: section, "0/36"))
            let scroller = try XCTUnwrap(firstNode(in: root) { $0.scrollAxis == .vertical })

            XCTAssertTrue(
                result.runtime.scrollToDescendant(title, anchorY: 0),
                scrollReadiness(in: result.runtime, scroller: scroller))
            let scene = result.runtime.renderScene(at: 0)
            XCTAssertGreaterThan(scroller.scrollOffset, 0, "the input example must be reached by scrolling")

            let titleBounds = try paintedTextBounds(of: title, in: scene)
            let detailBounds = try paintedTextBounds(of: detail, in: scene)
            let validationBounds = try paintedTextBounds(of: validation, in: scene)
            let countBounds = try paintedTextBounds(of: count, in: scene)

            XCTAssertLessThanOrEqual(
                titleBounds.maxY, detailBounds.minY,
                "\(width)pt: the card title must not paint over its explanatory text")
            XCTAssertLessThanOrEqual(
                detailBounds.maxY, validationBounds.minY,
                "\(width)pt: the validation message must remain below the input card header")
            XCTAssertLessThanOrEqual(
                validationBounds.maxX, countBounds.minX,
                "\(width)pt: the invalid-name message must not paint over its character count")
        }
    }
}
