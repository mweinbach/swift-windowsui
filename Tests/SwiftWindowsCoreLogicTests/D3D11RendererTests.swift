import SwiftWindowsCore
import SwiftWindowsGraphics

import XCTest

@testable import SwiftWindowsRendererD3D11

final class D3D11RendererTests: XCTestCase {
    func testDirect2DFactoryCanBeCreated() async throws {
        try await MainActor.run {
            try D3D11Renderer.validateDirect2DInteropForTesting()
        }
    }

    func testShaderSourceCompiles() async throws {
        try await MainActor.run {
            try D3D11Renderer.validateShaderSourceForTesting()
        }
    }

    func testPixelAlignedBitmapRectUsesBitmapDimensions() {
        let rect = Rect(x: 10.25, y: 5.5, width: 18.8, height: 9.6)
        let bitmapSize = IntSize(width: 29, height: 15)

        let aligned = makePixelAlignedBitmapRect(from: rect, bitmapSize: bitmapSize, scaleFactor: 1.5)

        XCTAssertEqual(aligned, Rect(x: 15, y: 8, width: 29, height: 15))
    }

    func testLogicalBitmapRectUsesBitmapDimensionsAtScale() {
        let rect = Rect(x: 10.25, y: 5.5, width: 18.8, height: 9.6)
        let bitmapSize = IntSize(width: 29, height: 15)

        let aligned = makeLogicalBitmapRect(from: rect, bitmapSize: bitmapSize, scaleFactor: 1.5)

        XCTAssertEqual(aligned, Rect(x: 10, y: 16.0 / 3.0, width: 58.0 / 3.0, height: 10))
    }

    func testCanonicalFrameGradientKeepsOneUnmaskedDraw() {
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let gradient = LinearGradient(startColor: red, endColor: blue, axis: .horizontal)
        let plan = FrameLinearGradientPlan(gradient)

        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.stops.map(\.position), [0, 1])
        XCTAssertEqual(plan.stops.map(\.color), [red, blue])
        XCTAssertEqual(plan.segmentMode(at: 0), 0)
    }

    func testFrameGradientPlanPreservesMiddleStopsAndEndpointExtensions() {
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let green = Color(red: 0, green: 1, blue: 0, alpha: 0.65)
        let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: red, position: 0.2),
                GradientStop(color: green, position: 0.45),
                GradientStop(color: blue, position: 0.8),
            ], axis: .horizontal)
        let plan = FrameLinearGradientPlan(gradient)

        XCTAssertEqual(plan.segments.count, 4)
        XCTAssertEqual(plan.stops.map(\.position), [0, 0.2, 0.45, 0.8, 1])
        XCTAssertEqual(plan.stops.map(\.color), [red, red, green, blue, blue])
        XCTAssertEqual(plan.segments.indices.map(plan.segmentMode(at:)), [1, 1, 1, 2])
    }

    func testFrameGradientHardStopsStayDuplicatedWithoutDoubleOwningBoundary() {
        let red = Color(red: 1, green: 0, blue: 0, alpha: 0.4)
        let blue = Color(red: 0, green: 0, blue: 1, alpha: 0.6)
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: red, position: 0),
                GradientStop(color: red, position: 0.5),
                GradientStop(color: blue, position: 0.5),
                GradientStop(color: blue, position: 1),
            ], axis: .vertical)
        let plan = FrameLinearGradientPlan(gradient)

        XCTAssertEqual(plan.segments.count, 2)
        XCTAssertEqual(plan.stops.map(\.position), [0, 0.5, 0.5, 1])
        XCTAssertEqual(plan.stops.map(\.color), [red, red, blue, blue])
        XCTAssertEqual(plan.segmentMode(at: 0), 1)
        XCTAssertEqual(plan.segmentMode(at: 1), 2)
    }

    func testFrameGradientNativeStopsAreSortedFiniteAndBounded() {
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
        var stops = [
            GradientStop(color: red, position: .nan),
            GradientStop(color: blue, position: .infinity),
        ]
        stops.append(
            contentsOf: (0..<256).reversed().map { index in
                GradientStop(
                    color: index.isMultiple(of: 2) ? red : blue,
                    position: Float(index + 1) / 257)
            })
        let plan = FrameLinearGradientPlan(LinearGradient(stops: stops, axis: .horizontal))

        XCTAssertLessThanOrEqual(plan.segments.count, LinearGradient.maximumRenderedStops)
        XCTAssertLessThanOrEqual(plan.stops.count, LinearGradient.maximumRenderedStops * 2)
        XCTAssertEqual(plan.stops.first?.position, 0)
        XCTAssertEqual(plan.stops.last?.position, 1)
        XCTAssertTrue(plan.stops.allSatisfy { $0.position.isFinite })
        XCTAssertTrue(zip(plan.stops, plan.stops.dropFirst()).allSatisfy { $0.position <= $1.position })
    }
}
