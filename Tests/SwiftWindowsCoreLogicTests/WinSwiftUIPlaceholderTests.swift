import XCTest
import Foundation
import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private func makeNode<V: View>(_ view: V) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 800, height: 600) },
        invalidateHandler: {}
    )
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func allTexts(in node: ViewNode) -> [String] {
    var texts: [String] = []
    if let text = node.text {
        texts.append(text)
    }
    for child in node.children {
        texts.append(contentsOf: allTexts(in: child))
    }
    return texts
}

final class WinSwiftUIPlaceholderTests: XCTestCase {
    func testMapRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(Map())
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Map") }))
        }
    }

    func testChartRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(Chart {
                BarMark(x: PlottableValue("X", 1), y: PlottableValue("Y", 2))
            })
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Chart") }))
        }
    }

    func testVideoPlayerRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(VideoPlayer<EmptyView>())
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Video") }))
        }
    }

    func testPDFViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(PDFView(url: URL(fileURLWithPath: "C:\\test.pdf")))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("PDF") }))
        }
    }

    func testWebViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(WebView(url: URL(fileURLWithPath: "https://example.com")))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("WebView") }))
        }
    }

    func testTipViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            struct TestTip: Tip {
                typealias Title = Text
                typealias Message = Text
                typealias Image = WinSwiftUI.Image
                var title: Text { Text("Test") }
            }
            let node = makeNode(TipView(TestTip()))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Tip") }))
        }
    }

    func testMapKitMapRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(MapKitMap())
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Map") }))
        }
    }

    func testAVPlayerViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(AVPlayerView())
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("AVPlayer") }))
        }
    }

    func testLivePhotoViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(LivePhotoView())
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Live Photo") }))
        }
    }

    func testCameraRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(Camera())
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Camera") }))
        }
    }

    func testSpriteViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(SpriteView(scene: "test"))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("SpriteKit") }))
        }
    }

    func testSceneViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(SceneView(scene: "test"))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("SceneKit") }))
        }
    }

    func testRealityViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(RealityView())
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("RealityKit") }))
        }
    }

    func testModel3DRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(Model3D(url: URL(fileURLWithPath: "C:\\test.usdz")))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("3D Model") }))
        }
    }

    func testQuickLookPreviewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(QuickLookPreview(url: URL(fileURLWithPath: "C:\\test.jpg")))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Quick Look") }))
        }
    }

    func testStoreViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(StoreView(ids: ["com.test.product"]))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("App Store") }))
        }
    }

    func testProductViewRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(ProductView(id: "com.test.product"))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Product") }))
        }
    }

    func testInAppPurchaseButtonRendersPlaceholderWithLabel() async {
        await MainActor.run {
            let node = makeNode(InAppPurchaseButton(productID: "com.test.product"))
            let texts = allTexts(in: node)
            XCTAssertTrue(texts.contains(where: { $0.contains("Purchase") }))
        }
    }
}
