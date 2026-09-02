import Foundation
import SwiftWindowsCore
import SwiftWindowsUI
import XCTest

@testable import WinSwiftUI

final class LocalizedTextResourceLookupTests: XCTestCase {
    func testExplicitNamedTableLooksUpRetainedText() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle([
                "Localizable": ["TITLE": "Default title"],
                "Account": ["TITLE": "Account title"],
            ]) { bundle in
                XCTAssertEqual(
                    bundle.localizedString(forKey: "TITLE", value: nil, table: "Account"),
                    "Account title"
                )
                assertLocalizedText(
                    Text(LocalizedStringKey("TITLE"), tableName: "Account", bundle: bundle),
                    equals: "Account title"
                )
            }
        }
    }

    func testOmittedNilAndEmptyTablesUseLocalizableInExplicitBundle() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle([
                "Localizable": ["TITLE": "Default title"],
                "Account": ["TITLE": "Account title"],
            ]) { bundle in
                let key = LocalizedStringKey("TITLE")
                assertLocalizedText(Text(key, bundle: bundle), equals: "Default title")
                assertLocalizedText(Text(key, tableName: nil, bundle: bundle), equals: "Default title")
                assertLocalizedText(Text(key, tableName: "", bundle: bundle), equals: "Default title")
            }
        }
    }

    func testMissingKeyFallsBackWithoutSearchingAnotherTable() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle([
                "Localizable": ["Only in default": "Do not borrow this translation"],
                "Account": ["OTHER": "Another account entry"],
            ]) { bundle in
                assertLocalizedText(
                    Text(LocalizedStringKey("Only in default"), tableName: "Account", bundle: bundle),
                    equals: "Only in default"
                )
            }
        }
    }

    func testMissingTableFallsBackToOriginalKey() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle([
                "Localizable": ["Missing table key": "Do not borrow this translation"]
            ]) { bundle in
                assertLocalizedText(
                    Text(LocalizedStringKey("Missing table key"), tableName: "Absent", bundle: bundle),
                    equals: "Missing table key"
                )
            }
        }
    }

    func testEmptyLocalizedValueDoesNotFallBackToKey() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle(["Localizable": ["EMPTY_VALUE": ""]]) { bundle in
                assertLocalizedText(Text(LocalizedStringKey("EMPTY_VALUE"), bundle: bundle), equals: "")
            }
        }
    }

    func testExplicitBundlesKeepIndependentTranslationsForSameKeyAndTable() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle(["Account": ["TITLE": "First bundle"]]) { first in
                try withLocalizedTextBundle(["Account": ["TITLE": "Second bundle"]]) { second in
                    let key = LocalizedStringKey("TITLE")
                    assertLocalizedText(Text(key, tableName: "Account", bundle: first), equals: "First bundle")
                    assertLocalizedText(Text(key, tableName: "Account", bundle: second), equals: "Second bundle")
                    assertLocalizedText(Text(key, tableName: "Account", bundle: first), equals: "First bundle")
                }
            }
        }
    }

    func testUnicodeAndEscapedCharactersReachRetainedText() async throws {
        try await MainActor.run {
            let expected = "設定 \"München\" — Καλημέρα 👩🏽‍💻\nSecond\tline"
            try withLocalizedTextBundle(["Account": ["UNICODE": expected]]) { bundle in
                assertLocalizedText(
                    Text(LocalizedStringKey("UNICODE"), tableName: "Account", bundle: bundle),
                    equals: expected
                )
            }
        }
    }

    func testTranslatorCommentsDoNotAffectLookupOrOutput() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle(["Account": ["TITLE": "Account title"]]) { bundle in
                let key = LocalizedStringKey("TITLE")
                assertLocalizedText(
                    Text(key, tableName: "Account", bundle: bundle, comment: "The account heading"),
                    equals: "Account title"
                )
                assertLocalizedText(
                    Text(key, tableName: "Account", bundle: bundle, comment: "Different translator context"),
                    equals: "Account title"
                )
            }
        }
    }

    func testResolvedTextSurvivesTextStylingAndConcatenation() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle(["Account": ["TITLE": "Account title"]]) { bundle in
                let localized = Text(LocalizedStringKey("TITLE"), tableName: "Account", bundle: bundle)
                assertLocalizedText(localized.bold().italic(), equals: "Account title")
                assertLocalizedText(localized + Text(verbatim: " / details"), equals: "Account title / details")
            }
        }
    }

    func testStringAndSubstringRemainUnlocalizedAfterExplicitLookup() async throws {
        try await MainActor.run {
            try withLocalizedTextBundle(["Localizable": ["TITLE": "Translated title"]]) { bundle in
                let stored: String = "TITLE"
                let substring = stored[...]
                assertLocalizedText(Text(LocalizedStringKey(stored), bundle: bundle), equals: "Translated title")
                assertLocalizedText(Text(stored), equals: "TITLE")
                assertLocalizedText(Text(substring), equals: "TITLE")
            }
        }
    }

    func testVerbatimTextRemainsLiteralAfterExplicitLookup() async throws {
        try await MainActor.run {
            let key = "**TITLE** %ld"
            try withLocalizedTextBundle(["Localizable": [key: "Translated title"]]) { bundle in
                assertLocalizedText(Text(LocalizedStringKey(key), bundle: bundle), equals: "Translated title")
                assertLocalizedText(Text(verbatim: key), equals: key)
            }
        }
    }

    func testConvenienceOverloadsPreserveMainBundleMissingKeyFallback() async {
        await MainActor.run {
            let missing = "winswiftui.missing.\(Foundation.UUID().uuidString)"
            let absentTable = "winswiftui.missing.table.\(Foundation.UUID().uuidString)"
            let key = LocalizedStringKey(missing)
            XCTAssertEqual(Bundle.main.localizedString(forKey: missing, value: nil, table: nil), missing)
            XCTAssertEqual(Bundle.main.localizedString(forKey: missing, value: nil, table: absentTable), missing)
            assertLocalizedText(Text(key), equals: missing)
            assertLocalizedText(Text(key, tableName: nil), equals: missing)
            assertLocalizedText(Text(key, tableName: absentTable), equals: missing)
            assertLocalizedText(Text(key, tableName: nil, bundle: nil, comment: nil), equals: missing)
            assertLocalizedText(Text(key, tableName: absentTable, bundle: .main), equals: missing)
        }
    }
}

@MainActor
private func assertLocalizedText(
    _ text: Text,
    equals expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(text.retainedTextDescription, expected, file: file, line: line)
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(
        canvasSizeProvider: { Size(width: 640, height: 240) },
        invalidateHandler: {}
    )
    let node = text.makeComponent(context: context).makeNode(runtime: runtime)
    XCTAssertEqual(node.text, expected, file: file, line: line)
}

@MainActor
private func withLocalizedTextBundle(
    _ tables: [String: [String: String]],
    body: (Bundle) throws -> Void
) throws {
    let manager = FileManager.default
    let temporaryParent = manager.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
    let directory = temporaryParent.appendingPathComponent(
        "winswiftui-localized-text-\(Foundation.UUID().uuidString).bundle", isDirectory: true
    ).standardizedFileURL
    guard directory.deletingLastPathComponent() == temporaryParent else {
        return XCTFail("The localization fixture must be an owned child of the temporary directory")
    }
    try manager.createDirectory(at: directory, withIntermediateDirectories: false)
    defer {
        if directory.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL == temporaryParent {
            try? manager.removeItem(at: directory)
        }
    }

    let info: [String: String] = [
        "CFBundleIdentifier": "org.winswiftui.localization.\(Foundation.UUID().uuidString)",
        "CFBundleName": "LocalizedTextFixture",
        "CFBundlePackageType": "BNDL",
        "CFBundleDevelopmentRegion": "en",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: directory.appendingPathComponent("Info.plist"))
    for (name, strings) in tables {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else {
            return XCTFail("Fixture table names must be single nonempty path components")
        }
        try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent(name + ".strings"))
    }
    let bundle = try XCTUnwrap(Bundle(url: directory), "Foundation must load the real resource fixture")
    XCTAssertEqual(bundle.bundleURL.standardizedFileURL, directory)
    for name in tables.keys {
        XCTAssertNotNil(bundle.url(forResource: name, withExtension: "strings"))
    }
    try body(bundle)
}
