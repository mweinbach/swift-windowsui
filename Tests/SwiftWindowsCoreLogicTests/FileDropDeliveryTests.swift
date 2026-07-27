import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class FileDropDeliveryTests: XCTestCase {
    @MainActor
    private final class FakeFileDropPayloadSource: FileDropPayloadSource {
        var paths: [String] = []
        var point: Point?
        private(set) var finishedHandles: [UInt] = []

        func filePaths(forDropHandle handle: UInt) -> [String] {
            paths
        }

        func clientPoint(forDropHandle handle: UInt) -> Point? {
            point
        }

        func finishDrop(handle: UInt) {
            finishedHandles.append(handle)
        }
    }

    @MainActor
    private static func makeContext() -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 200) },
            invalidateHandler: {}
        )
    }

    @MainActor
    private static func withFakeSource(_ body: (FakeFileDropPayloadSource) -> Void) {
        let fake = FakeFileDropPayloadSource()
        let original = FileDropManager.payloadSource
        FileDropManager.payloadSource = fake
        defer { FileDropManager.payloadSource = original }
        body(fake)
    }

    func testPayloadExtractsFileURLsAndClientPoint() async {
        await MainActor.run {
            Self.withFakeSource { fake in
                fake.paths = ["C:\\data\\a.txt", "C:\\data\\b c.png"]
                fake.point = Point(x: 40, y: 24)

                let payload = FileDropManager.payload(forDropHandle: 42)

                // URL(fileURLWithPath:).path normalizes backslashes to
                // forward slashes on Windows, so compare through URL.
                XCTAssertEqual(
                    payload?.fileURLs.map { $0.path },
                    fake.paths.map { URL(fileURLWithPath: $0).path })
                XCTAssertEqual(payload?.clientPoint, Point(x: 40, y: 24))
                XCTAssertTrue(payload?.fileURLs.allSatisfy { $0.isFileURL } ?? false)
                XCTAssertEqual(fake.finishedHandles, [42], "drop handle must always be released")
            }
        }
    }

    func testPayloadIsNilForEmptyDropButStillReleasesHandle() async {
        await MainActor.run {
            Self.withFakeSource { fake in
                fake.paths = []

                XCTAssertNil(FileDropManager.payload(forDropHandle: 7))
                XCTAssertEqual(fake.finishedHandles, [7])
            }
        }
    }

    func testPayloadDefaultsMissingPointToZero() async {
        await MainActor.run {
            Self.withFakeSource { fake in
                fake.paths = ["C:\\data\\a.txt"]
                fake.point = nil

                XCTAssertEqual(FileDropManager.payload(forDropHandle: 9)?.clientPoint, .zero)
            }
        }
    }

    func testPerformFileDropDeliversURLsToOnDropDestination() async {
        await MainActor.run {
            let dropped = [URL(fileURLWithPath: "C:\\dropped\\file.txt")]
            var received: [URL] = []
            var receivedCount = 0

            let view = Color.clear
                .frame(width: 200, height: 200)
                .onDrop(of: [.fileURL]) { providers, _ in
                    receivedCount = providers.count
                    received = providers.compactMap { $0.payload as? URL }
                    return true
                }

            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200)))
            let host = ComponentHost(runtime: runtime)
            host.setContent(view.makeComponent(context: Self.makeContext()))
            _ = runtime.renderFrame()

            let accepted = runtime.performFileDrop(dropped, at: Point(x: 100, y: 100))

            XCTAssertTrue(accepted)
            XCTAssertEqual(receivedCount, 1, "raw URL items must be wrapped into NSItemProviders")
            XCTAssertEqual(received.map { $0.path }, dropped.map { $0.path })
        }
    }

    func testPerformFileDropRespectsAcceptedContentTypes() async {
        await MainActor.run {
            let dropped = [URL(fileURLWithPath: "C:\\dropped\\file.txt")]
            var handlerCalled = false

            let view = Color.clear
                .frame(width: 200, height: 200)
                .onDrop(of: [.plainText]) { _, _ in
                    handlerCalled = true
                    return true
                }

            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200)))
            let host = ComponentHost(runtime: runtime)
            host.setContent(view.makeComponent(context: Self.makeContext()))
            _ = runtime.renderFrame()

            let accepted = runtime.performFileDrop(dropped, at: Point(x: 100, y: 100))

            XCTAssertFalse(accepted, "a text-only destination must not receive a file drop")
            XCTAssertFalse(handlerCalled)
        }
    }

    func testPerformFileDropWithoutDestinationReturnsFalse() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200)))
            let host = ComponentHost(runtime: runtime)
            host.setContent(Text("no drop here").makeComponent(context: Self.makeContext()))
            _ = runtime.renderFrame()

            let accepted = runtime.performFileDrop(
                [URL(fileURLWithPath: "C:\\dropped\\file.txt")],
                at: Point(x: 100, y: 100)
            )

            XCTAssertFalse(accepted)
        }
    }

    func testPerformFileDropValidateGateDeclines() async {
        await MainActor.run {
            // A destination whose validator declines must not receive payloads.
            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200)))
            var payloadDelivered = false
            let target = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                isHitTestVisible: true
            )
            target.isDropDestinationEnabled = true
            target.onValidateDrop = { _, _ in false }
            target.onDropPayloads = { _, _ in
                payloadDelivered = true
                return true
            }
            runtime.root.addChild(target)
            _ = runtime.renderFrame()

            let accepted = runtime.performFileDrop(
                [URL(fileURLWithPath: "C:\\dropped\\file.txt")],
                at: Point(x: 100, y: 100)
            )

            XCTAssertFalse(accepted)
            XCTAssertFalse(payloadDelivered)
        }
    }
}
