import Foundation
import XCTest

@testable import SwiftWindowsDemo

/// Pins the Windows Foundation URL value boundary without reading either path.
@MainActor
final class DemoFileURLConstructionTests: XCTestCase {
    func testLiteralBackslashConstructorNormalizationHasNoDistinctURLSpelling() async throws {
        #if os(Windows)
            let normalized = try XCTUnwrap(URL(string: "file:///C:/bad\\name"))
            let ordinary = try XCTUnwrap(URL(string: "file:///C:/bad/name"))

            XCTAssertEqual(normalized, ordinary)
            XCTAssertEqual(normalized.absoluteString, ordinary.absoluteString)
            XCTAssertEqual(normalized.relativeString, ordinary.relativeString)
            XCTAssertEqual(normalized.dataRepresentation, ordinary.dataRepresentation)
            XCTAssertEqual(normalized.path, ordinary.path)
            XCTAssertEqual(normalized.relativePath, ordinary.relativePath)
            XCTAssertEqual(normalized.hasDirectoryPath, ordinary.hasDirectoryPath)
            XCTAssertEqual(normalized.baseURL, ordinary.baseURL)
            XCTAssertEqual(normalized.isFileURL, ordinary.isFileURL)
            let normalizedComponents = try XCTUnwrap(URLComponents(url: normalized, resolvingAgainstBaseURL: false))
            let ordinaryComponents = try XCTUnwrap(URLComponents(url: ordinary, resolvingAgainstBaseURL: false))
            XCTAssertEqual(normalizedComponents, ordinaryComponents)
            XCTAssertEqual(normalizedComponents.string, ordinaryComponents.string)
            XCTAssertEqual(normalizedComponents.percentEncodedPath, ordinaryComponents.percentEncodedPath)

            // Admission receives identical URL values; it must not blacklist
            // this ordinary path to guess text discarded by the constructor.
            let identity = try DemoFilePreviewService.validateFileURL(ordinary)
            XCTAssertEqual(identity, ordinary)
            XCTAssertEqual(try DemoFilePreviewService.validateFileURL(normalized), identity)

            // Percent encoding actually carries the forbidden backslash to
            // the validator. The existing rejection fixture uses this form.
            let escaped = try XCTUnwrap(URL(string: "file:///C:/bad%5Cname"))
            let escapedComponents = try XCTUnwrap(URLComponents(url: escaped, resolvingAgainstBaseURL: false))
            XCTAssertTrue(try XCTUnwrap(escapedComponents.percentEncodedPath.removingPercentEncoding).contains("\\"))
            XCTAssertThrowsError(try DemoFilePreviewService.validateFileURL(escaped)) { error in
                XCTAssertEqual(error as? DemoFilePreviewServiceError, .invalidFileURL)
            }
        #endif
    }
}
