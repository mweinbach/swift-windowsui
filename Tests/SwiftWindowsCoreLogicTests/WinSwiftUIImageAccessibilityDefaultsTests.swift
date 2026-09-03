import CUIAInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public Image semantics through the retained UIA snapshot adapter, without
/// a native window or COM provider. Generic frame/aspectRatio forwarding is
/// outside this slice; a label applied after frame is not qualified here.
@MainActor
final class WinSwiftUIImageAccessibilityDefaultsTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let runtime: RetainedViewRuntime
        let node: ViewNode
        let source: RuntimeUIAElementTreeSource

        init<Content: View>(_ content: Content) {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200))
            root.resolvedFrame = root.frame
            runtime = RetainedViewRuntime(root: root)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 200, height: 200) }, invalidateHandler: {})
            node = content.makeComponent(context: context).makeNode(runtime: runtime)
            root.addChild(node)
            source = RuntimeUIAElementTreeSource(runtime: runtime)
        }

        var descendants: [UIAElementSnapshot] {
            source.uiaElementSnapshots().filter { $0.id != UIAProviderBridge.rootElementID }
        }
    }

    private func bitmap() -> BitmapSurface {
        BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 0, 255]))
    }

    private func representations() -> [AnyView] {
        [
            AnyView(Image(bitmap: bitmap())),
            AnyView(Image(bitmap: bitmap()).resizable().scaledToFit()),
            AnyView(Image(systemName: "gearshape")),
            AnyView(Image(systemName: "gearshape").symbolVariant([.circle, .slash])),
        ]
    }

    private func withBitmapFile(_ body: (String) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-accessibility-\(UUID().uuidString).bmp")
        try bitmap().writeBMP(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url.path)
    }

    private func assertSingleImage(
        _ fixture: Fixture, name: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let snapshots = fixture.descendants
        XCTAssertEqual(snapshots.count, 1, file: file, line: line)
        let image = try XCTUnwrap(snapshots.first, file: file, line: line)
        XCTAssertEqual(image.controlType, Int32(SWU_UIA_CONTROL_TYPE_IMAGE), file: file, line: line)
        if let name { XCTAssertEqual(image.name, name, file: file, line: line) }
    }

    func testUnlabelledBitmapIsAnImageDescendant() async throws {
        let fixture = Fixture(Image(bitmap: bitmap()))
        try assertSingleImage(fixture, name: "")
        XCTAssertTrue(fixture.node.accessibilityTraits.contains(.isImage))
        XCTAssertFalse(fixture.node.isAccessibilityImage, "The removable trait owns the default role")
    }

    func testLabelledBitmapIsOneNamedImage() async throws {
        try assertSingleImage(Fixture(Image(bitmap: bitmap()).accessibilityLabel("Mark")), name: "Mark")
    }

    func testUnlabelledSystemSymbolIsAnImageDescendant() async throws {
        try assertSingleImage(Fixture(Image(systemName: "gearshape")))
    }

    func testSystemSymbolInitializerLabelCanBeOverridden() async throws {
        try assertSingleImage(
            Fixture(Image(systemName: "gearshape", label: Text("Settings"))), name: "Settings")
        try assertSingleImage(
            Fixture(Image(systemName: "gearshape", label: Text("Settings")).accessibilityLabel("Preferences")),
            name: "Preferences")
    }

    func testNamedBitmapSourceIsOneNamedImage() async throws {
        try withBitmapFile { path in
            let fixture = Fixture(Image(path, label: Text("Resource mark")))
            XCTAssertNotNil(fixture.node.bitmapSurface)
            try assertSingleImage(fixture, name: "Resource mark")
        }
    }

    func testMissingNamedSourceKeepsImageSemanticsWithoutClaimingDecode() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-image-\(UUID().uuidString).png").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let fixture = Fixture(Image(path, label: Text("Unavailable image")))
        XCTAssertNil(fixture.node.bitmapSurface)
        try assertSingleImage(fixture, name: "Unavailable image")
        XCTAssertTrue(Fixture(Image(decorative: path)).descendants.isEmpty)
    }

    func testDecorativeResourceAndTypedFitAreOmittedUnlessExplicitlyUnhidden() async throws {
        try withBitmapFile { path in
            XCTAssertTrue(Fixture(Image(decorative: path).accessibilityLabel("Decoration")).descendants.isEmpty)
            XCTAssertTrue(
                Fixture(Image(decorative: path).resizable().scaledToFit().accessibilityLabel("Decoration"))
                    .descendants.isEmpty)
            try assertSingleImage(
                Fixture(Image(decorative: path).accessibilityHidden(false).accessibilityLabel("Restored")),
                name: "Restored")
        }
    }

    func testExplicitHiddenModifierOmitsEveryPublicRepresentation() async {
        for image in representations() {
            XCTAssertTrue(Fixture(image.accessibilityLabel("Hidden").accessibilityHidden(true)).descendants.isEmpty)
        }
    }

    func testRemovingImageTraitOmitsUnlabelledBitmapAndTypedFit() async {
        for image in [AnyView(Image(bitmap: bitmap())), AnyView(Image(bitmap: bitmap()).resizable().scaledToFit())] {
            let fixture = Fixture(image.accessibilityRemoveTraits(.isImage))
            XCTAssertFalse(fixture.node.accessibilityTraits.contains(.isImage))
            XCTAssertTrue(fixture.descendants.isEmpty)
        }
    }

    func testRemovingImageTraitPreservesLabelWithoutReinsertingImageRole() async throws {
        for image in representations() {
            let fixture = Fixture(image.accessibilityLabel("Role override").accessibilityRemoveTraits(.isImage))
            XCTAssertFalse(fixture.node.accessibilityTraits.contains(.isImage))
            XCTAssertFalse(fixture.node.isAccessibilityImage)
            XCTAssertEqual(fixture.descendants.count, 1)
            let snapshot = try XCTUnwrap(fixture.descendants.first)
            XCTAssertEqual(snapshot.name, "Role override")
            XCTAssertNotEqual(snapshot.controlType, Int32(SWU_UIA_CONTROL_TYPE_IMAGE))
        }
    }

    func testExplicitlyAddingImageTraitAgainRestoresEveryRepresentation() async throws {
        for image in representations() {
            try assertSingleImage(
                Fixture(
                    image.accessibilityRemoveTraits(.isImage).accessibilityAddTraits(.isImage)
                        .accessibilityLabel("Restored image")), name: "Restored image")
        }
    }

    func testExplicitButtonTraitTakesPrecedenceOverImageDefault() async throws {
        for image in representations() {
            let fixture = Fixture(image.accessibilityLabel("Action image").accessibilityAddTraits(.isButton))
            XCTAssertEqual(fixture.descendants.count, 1)
            let snapshot = try XCTUnwrap(fixture.descendants.first)
            XCTAssertEqual(snapshot.name, "Action image")
            XCTAssertEqual(snapshot.controlType, Int32(SWU_UIA_CONTROL_TYPE_BUTTON))
        }
    }

    func testTypedFitHasOneImageAtItsOwnSemanticRoot() async throws {
        let fixture = Fixture(Image(bitmap: bitmap()).resizable().scaledToFit())
        try assertSingleImage(fixture, name: "")
        XCTAssertNotNil(fixture.node.aspectFitLayout)
        XCTAssertNil(fixture.node.selectedContentRole)
        let leaf = try XCTUnwrap(fixture.node.children.first)
        XCTAssertNotNil(leaf.bitmapSurface)
        XCTAssertTrue(leaf.accessibilityTraits.isEmpty)
        XCTAssertNil(leaf.accessibilityLabel)
        XCTAssertFalse(leaf.isAccessibilityHidden)
        XCTAssertTrue(leaf.parent === fixture.node)
    }

    func testTypedFitLabelDoesNotMovePaintMetadataFromBitmap() async throws {
        let fixture = Fixture(
            Image(bitmap: bitmap()).resizable().interpolation(.none).scaledToFit().accessibilityLabel("Fitted mark"))
        try assertSingleImage(fixture, name: "Fitted mark")
        let leaf = try XCTUnwrap(fixture.node.children.first)
        XCTAssertEqual(leaf.imageResizingMode, .stretch)
        XCTAssertEqual(leaf.imageInterpolation, .none)
        XCTAssertTrue(leaf.imageUsesBitmapResizing)
        XCTAssertNil(fixture.node.bitmapSurface)
        XCTAssertNil(fixture.node.imageResizingMode)
    }

    func testCompositeSymbolVariantsExposeExactlyOneNamedImage() async throws {
        for variants in [SymbolVariants.circle, .square, .rectangle, .slash, [.circle, .fill, .slash]] {
            let fixture = Fixture(Image(systemName: "gearshape", label: Text("Settings")).symbolVariant(variants))
            try assertSingleImage(fixture, name: "Settings")
            XCTAssertEqual(fixture.node.nodeTag, "symbol-variant")
            let icon = try XCTUnwrap(fixture.node.children.first)
            XCTAssertTrue(icon.isAccessibilityHidden)
            XCTAssertTrue(icon.accessibilityTraits.isEmpty)
            XCTAssertNil(icon.accessibilityLabel)
        }
    }

    func testCompositeSymbolKeepsPaintMetadataOnRootAndIcon() async throws {
        let fixture = Fixture(
            Image(systemName: "gearshape", variableValue: 0.5).resizable(resizingMode: .tile)
                .symbolVariant([.circle, .fill, .slash]).accessibilityLabel("Decorated settings"))
        try assertSingleImage(fixture, name: "Decorated settings")
        let icon = try XCTUnwrap(fixture.node.children.first)
        for node in [fixture.node, icon] {
            XCTAssertEqual(node.symbolVariableValue, 0.5)
            XCTAssertEqual(node.symbolVariants, [.circle, .fill, .slash])
            XCTAssertEqual(node.imageResizingMode, .tile)
            XCTAssertEqual(node.imageCapInsets, .zero)
        }
        XCTAssertEqual(icon.text, "\u{E713}")
        XCTAssertEqual(icon.textStyle.weight, .bold)
        XCTAssertEqual(fixture.node.children.count, 2)
        XCTAssertEqual(fixture.node.children[1].nodeTag, "symbol-variant-slash")
    }

    func testUnlabelledFrameProjectsOnlyItsImageLeafAndKeepsLayout() async throws {
        let fixture = Fixture(Image(bitmap: bitmap()).resizable().frame(width: 32, height: 24))
        try assertSingleImage(fixture, name: "")
        XCTAssertEqual(fixture.node.preferredSize, Size(width: 32, height: 24))
        XCTAssertTrue(fixture.node.accessibilityTraits.isEmpty)
        XCTAssertNil(fixture.node.selectedContentRole)
        XCTAssertTrue(try XCTUnwrap(fixture.node.children.first).parent === fixture.node)
    }

    func testLabelBeforeFrameRemainsOnTheSingleImageLeaf() async throws {
        let fixture = Fixture(
            Image(bitmap: bitmap()).resizable().accessibilityLabel("Inner label").frame(width: 32, height: 24))
        try assertSingleImage(fixture, name: "Inner label")
        XCTAssertNil(fixture.node.accessibilityLabel)
        XCTAssertNil(fixture.node.selectedContentRole)
    }

    func testLabelledNonImageFrameRemainsAGroup() async throws {
        let fixture = Fixture(Color.clear.frame(width: 32, height: 24).accessibilityLabel("Layout"))
        XCTAssertEqual(fixture.descendants.count, 1)
        let snapshot = try XCTUnwrap(fixture.descendants.first)
        XCTAssertEqual(snapshot.name, "Layout")
        XCTAssertEqual(snapshot.controlType, Int32(SWU_UIA_CONTROL_TYPE_GROUP))
    }

    func testExplicitFrameChildBehaviorsAreNotOverriddenByImageDefault() async throws {
        for behavior in [AccessibilityChildBehavior.ignore, .combine, .contain] {
            let fixture = Fixture(
                Image(bitmap: bitmap()).accessibilityLabel("Child").frame(width: 32, height: 24)
                    .accessibilityElement(children: behavior).accessibilityLabel("Authored group"))
            let snapshots = fixture.descendants
            XCTAssertEqual(snapshots.count, behavior == .contain ? 2 : 1)
            let group = try XCTUnwrap(snapshots.first)
            XCTAssertEqual(group.name, "Authored group")
            XCTAssertEqual(group.controlType, Int32(SWU_UIA_CONTROL_TYPE_GROUP))
            XCTAssertEqual(
                snapshots.filter { $0.controlType == Int32(SWU_UIA_CONTROL_TYPE_IMAGE) }.count,
                behavior == .contain ? 1 : 0)
        }
    }

    func testViewThatFitsProjectsTheSelectedImageOnly() async throws {
        let fixture = Fixture(
            ViewThatFits {
                Image(bitmap: bitmap()).accessibilityLabel("Selected")
                Image(bitmap: bitmap()).accessibilityLabel("Not selected")
            })
        try assertSingleImage(fixture, name: "Selected")
        XCTAssertNotNil(fixture.node.selectedContentRole)
        XCTAssertEqual(fixture.node.children.count, 1)
        XCTAssertTrue(try XCTUnwrap(fixture.node.children.first).parent === fixture.node)
    }

    func testInternalBitmapPrimitiveDoesNotAcquirePublicImageSemantics() async {
        let root = ViewNode()
        let runtime = RetainedViewRuntime(root: root)
        let primitive = Controls.image(bitmap())
        root.addChild(primitive)
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        XCTAssertTrue(primitive.accessibilityTraits.isEmpty)
        XCTAssertFalse(primitive.isAccessibilityImage)
        XCTAssertEqual(source.uiaElementSnapshots().count, 1, "Only the neutral host root is projected")
    }
}
