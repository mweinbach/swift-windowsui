import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class DocumentFileServiceTests: XCTestCase {
    func testBoundedReadsPreserveTheActualFileBytes() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let samples = [
                    Data(),
                    Data(" \t\r\nline\rnext\n".utf8),
                    Data("\u{FEFF}e\u{301}👨‍👩‍👧‍👦\r\n".utf8),
                    Data([0, 0xFF, 0x80, 0x7F]),
                ]
                for (index, bytes) in samples.enumerated() {
                    let url = fixture.file("read-\(index).txt")
                    try bytes.write(to: url)
                    XCTAssertEqual(try fixture.service.readRegularFile(at: url, maximumBytes: bytes.count), bytes)
                    XCTAssertEqual(try fixture.service.readRegularFile(at: url, maximumBytes: bytes.count + 1), bytes)
                }
                XCTAssertEqual(LiveDocumentFileService.defaultMaximumReadBytes, 16 * 1024 * 1024)
            }
        }
    }

    func testReadLimitCoversMultipleChunksAndDetectsTheOverflowByte() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let url = fixture.file("chunks.bin")
                let bytes = Data((0..<(64 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0) })
                try bytes.write(to: url)

                XCTAssertEqual(try fixture.service.readRegularFile(at: url, maximumBytes: bytes.count), bytes)
                for limit in [1, 64 * 1024, bytes.count - 1] {
                    XCTAssertThrowsError(try fixture.service.readRegularFile(at: url, maximumBytes: limit)) {
                        XCTAssertEqual($0 as? DocumentFileServiceError, .readLimitExceeded(maximumBytes: limit))
                    }
                }
                // Overflow cleanup releases the read handle before another
                // operation tries to atomically replace this same Windows file.
                let replacement = Data("after failed read".utf8)
                XCTAssertEqual(
                    try fixture.service.writeRegularFile(to: url, provideData: { _ in replacement }, validate: {}),
                    replacement)
                XCTAssertEqual(try fixture.bytes(at: url), replacement)
            }
        }
    }

    func testZeroNegativeAndMaximumIntegerReadLimitsDoNotAllocateFromTheLimit() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let empty = fixture.file("empty.txt")
                let oneByte = fixture.file("one-byte.txt")
                try Data().write(to: empty)
                try Data([7]).write(to: oneByte)

                XCTAssertEqual(try fixture.service.readRegularFile(at: empty, maximumBytes: 0), Data())
                XCTAssertThrowsError(try fixture.service.readRegularFile(at: oneByte, maximumBytes: 0)) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .readLimitExceeded(maximumBytes: 0))
                }
                XCTAssertThrowsError(try fixture.service.readRegularFile(at: oneByte, maximumBytes: -1)) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .invalidReadLimit)
                }
                XCTAssertEqual(try fixture.service.readRegularFile(at: oneByte, maximumBytes: Int.max), Data([7]))
            }
        }
    }

    func testReadRejectsNonFileURLsDirectoriesPackagesAndMissingFiles() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let remote = try XCTUnwrap(URL(string: "https://example.invalid/document.txt"))
                XCTAssertThrowsError(try fixture.service.readRegularFile(at: remote, maximumBytes: 10)) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .invalidFileURL)
                }
                let package = fixture.file("document.bundle")
                try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
                let child = package.appendingPathComponent("contents.txt")
                try Data("unchanged".utf8).write(to: child)
                for url in [fixture.directory, package] {
                    XCTAssertThrowsError(try fixture.service.readRegularFile(at: url, maximumBytes: 10)) {
                        XCTAssertEqual($0 as? DocumentFileServiceError, .notRegularFile)
                    }
                }
                XCTAssertThrowsError(
                    try fixture.service.readRegularFile(at: fixture.file("missing.txt"), maximumBytes: 10))
                XCTAssertEqual(try fixture.bytes(at: child), Data("unchanged".utf8))
            }
        }
    }

    func testDecodedNULURLCannotAliasALiteralPercentEncodedFilename() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let literal = fixture.file("bad%00name.txt")
                let old = Data("literal percent filename".utf8)
                try old.write(to: literal)
                let embeddedNUL = try XCTUnwrap(
                    URL(string: "bad%00name.txt", relativeTo: fixture.directory)?.absoluteURL)
                XCTAssertTrue(embeddedNUL.path(percentEncoded: false).utf16.contains(0))
                XCTAssertFalse(literal.path(percentEncoded: false).utf16.contains(0))

                XCTAssertEqual(try fixture.service.readRegularFile(at: literal, maximumBytes: old.count), old)
                XCTAssertThrowsError(try fixture.service.readRegularFile(at: embeddedNUL, maximumBytes: 100)) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .invalidFileURL)
                }
                var serializations = 0
                XCTAssertThrowsError(
                    try fixture.service.writeRegularFile(
                        to: embeddedNUL,
                        provideData: { _ in
                            serializations += 1
                            return Data("wrong".utf8)
                        },
                        validate: {})
                ) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .invalidFileURL)
                }
                XCTAssertEqual(serializations, 0)
                XCTAssertEqual(try fixture.bytes(at: literal), old)
                XCTAssertEqual(try fixture.childNames(), ["bad%00name.txt"])
            }
        }
    }

    func testWritesCreateAndReplaceFilesAndReturnTheExactCommittedData() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let url = fixture.file("saved.txt")
                for bytes in [Data("first".utf8), Data([0, 0xFF, 10, 13, 42]), Data()] {
                    var order: [String] = []
                    let result = try fixture.service.writeRegularFile(
                        to: url,
                        provideData: { destination in
                            XCTAssertEqual(destination, url)
                            order.append("serialize")
                            return bytes
                        },
                        validate: { order.append("validate") })

                    XCTAssertEqual(order, ["validate", "serialize", "validate", "validate"])
                    XCTAssertEqual(result, bytes)
                    XCTAssertEqual(try fixture.bytes(at: url), bytes)
                    XCTAssertEqual(try fixture.childNames(), ["saved.txt"])
                }
            }
        }
    }

    func testRemoteFileURLAuthorityCannotBeDiscardedToReachAnOwnedLocalFile() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let local = fixture.file("protected.txt")
                let old = Data("local bytes".utf8)
                try old.write(to: local)
                var components = try XCTUnwrap(URLComponents(url: local, resolvingAgainstBaseURL: true))
                components.host = "other-host"
                let remoteAuthority = try XCTUnwrap(components.url)

                XCTAssertThrowsError(try fixture.service.readRegularFile(at: remoteAuthority, maximumBytes: 100)) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .invalidFileURL)
                }
                var serializations = 0
                XCTAssertThrowsError(
                    try fixture.service.writeRegularFile(
                        to: remoteAuthority,
                        provideData: { _ in
                            serializations += 1
                            return Data("wrong target".utf8)
                        },
                        validate: {})
                ) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .invalidFileURL)
                }
                fixture.provider.openOutcome = .selected([remoteAuthority])
                assertDocumentDialogFailure(
                    fixture.service.chooseOpenURL(types: [.utf8PlainText], owner: .standalone),
                    DocumentFileServiceError.invalidFileURL)
                XCTAssertEqual(serializations, 0)
                XCTAssertEqual(try fixture.bytes(at: local), old)

                components.host = "LOCALHOST"
                let localAuthority = try XCTUnwrap(components.url)
                XCTAssertEqual(try fixture.service.readRegularFile(at: localAuthority, maximumBytes: 100), old)
            }
        }
    }

    func testNativePickerUNCURLFormSurvivesURLValidationWithoutOpeningANetworkFile() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                // An explicit directory flag avoids filesystem probing during
                // URL construction. The fake provider chooses a URL only; this
                // fixture does not access the server or qualify network IO.
                let unc = URL(fileURLWithPath: "\\\\server\\share\\document.txt", isDirectory: false)
                XCTAssertNil(unc.host(percentEncoded: true))
                fixture.provider.openOutcome = .selected([unc])
                let outcome = fixture.service.chooseOpenURL(types: [.utf8PlainText], owner: .standalone)

                guard case .selected(let selected) = outcome else {
                    return XCTFail("The picker UNC form was rejected.")
                }
                XCTAssertEqual(selected, unc)
                XCTAssertTrue(try fixture.childNames().isEmpty)
            }
        }
    }

    func testSerializerFailurePreservesOldBytesAndDoesNotReachTheCommitValidator() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let url = fixture.file("saved.txt")
                let old = Data("old".utf8)
                try old.write(to: url)
                var order: [String] = []

                XCTAssertThrowsError(
                    try fixture.service.writeRegularFile(
                        to: url,
                        provideData: { _ in
                            order.append("serialize")
                            throw DocumentServiceFixtureError.encoding
                        },
                        validate: { order.append("validate") })
                ) {
                    XCTAssertEqual($0 as? DocumentServiceFixtureError, .encoding)
                }
                XCTAssertEqual(order, ["validate", "serialize"])
                XCTAssertEqual(try fixture.bytes(at: url), old)
                XCTAssertEqual(try fixture.childNames(), ["saved.txt"])
            }
        }
    }

    func testEveryOwnerValidationBoundaryCanPreventTheAtomicWrite() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let url = fixture.file("saved.txt")
                let old = Data("old".utf8)
                try old.write(to: url)
                for rejection in 1...3 {
                    var validations = 0
                    var serializations = 0
                    XCTAssertThrowsError(
                        try fixture.service.writeRegularFile(
                            to: url,
                            provideData: { _ in
                                serializations += 1
                                return Data("must not replace".utf8)
                            },
                            validate: {
                                validations += 1
                                if validations == rejection { throw DocumentServiceFixtureError.retired }
                            })
                    ) {
                        XCTAssertEqual($0 as? DocumentServiceFixtureError, .retired)
                    }
                    XCTAssertEqual(validations, rejection)
                    XCTAssertEqual(serializations, rejection == 1 ? 0 : 1)
                    XCTAssertEqual(try fixture.bytes(at: url), old)
                    XCTAssertEqual(try fixture.childNames(), ["saved.txt"])
                }
            }
        }
    }

    func testMutationDuringSerializationIsRejectedBeforeWriting() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let url = fixture.file("revision.txt")
                let old = Data("old".utf8)
                try old.write(to: url)
                var revision = 5
                var validations = 0

                XCTAssertThrowsError(
                    try fixture.service.writeRegularFile(
                        to: url,
                        provideData: { _ in
                            revision += 1
                            return Data("stale snapshot".utf8)
                        },
                        validate: {
                            validations += 1
                            guard revision == 5 else { throw DocumentServiceFixtureError.superseded }
                        })
                ) {
                    XCTAssertEqual($0 as? DocumentServiceFixtureError, .superseded)
                }
                XCTAssertEqual(validations, 2)
                XCTAssertEqual(try fixture.bytes(at: url), old)
            }
        }
    }

    func testFinalValidatorCannotReplaceARegularFileCheckWithADirectory() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let url = fixture.file("changed-to-directory")
                let child = url.appendingPathComponent("keep.txt")
                var validations = 0
                var serializations = 0

                XCTAssertThrowsError(
                    try fixture.service.writeRegularFile(
                        to: url,
                        provideData: { _ in
                            serializations += 1
                            return Data("not a directory".utf8)
                        },
                        validate: {
                            validations += 1
                            if validations == 3 {
                                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                                try Data("keep".utf8).write(to: child)
                            }
                        })
                ) {
                    XCTAssertEqual($0 as? DocumentFileServiceError, .notRegularFile)
                }
                XCTAssertEqual(validations, 3)
                XCTAssertEqual(serializations, 1)
                XCTAssertEqual(try fixture.bytes(at: child), Data("keep".utf8))
                XCTAssertEqual(try fixture.childNames(), ["changed-to-directory"])
            }
        }
    }

    func testInvalidWriteDestinationsAreRejectedBeforeSerialization() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let remote = try XCTUnwrap(URL(string: "https://example.invalid/document.txt"))
                for (url, expected) in [
                    (remote, DocumentFileServiceError.invalidFileURL),
                    (fixture.directory, DocumentFileServiceError.notRegularFile),
                ] {
                    var validations = 0
                    var serializations = 0
                    XCTAssertThrowsError(
                        try fixture.service.writeRegularFile(
                            to: url,
                            provideData: { _ in
                                serializations += 1
                                return Data()
                            },
                            validate: { validations += 1 })
                    ) {
                        XCTAssertEqual($0 as? DocumentFileServiceError, expected)
                    }
                    XCTAssertEqual(validations, 1)
                    XCTAssertEqual(serializations, 0)
                }
                XCTAssertTrue(try fixture.childNames().isEmpty)
            }
        }
    }

    func testFilesystemWriteFailureDoesNotCreateParentsOrDamageAnotherFile() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let neighbor = fixture.file("keep.txt")
                try Data("keep".utf8).write(to: neighbor)
                let destination = fixture.file("missing-parent").appendingPathComponent("save.txt")
                var serializations = 0
                XCTAssertThrowsError(
                    try fixture.service.writeRegularFile(
                        to: destination,
                        provideData: { _ in
                            serializations += 1
                            return Data("new".utf8)
                        },
                        validate: {}))

                XCTAssertEqual(serializations, 1)
                XCTAssertEqual(try fixture.bytes(at: neighbor), Data("keep".utf8))
                XCTAssertEqual(try fixture.childNames(), ["keep.txt"])
            }
        }
    }

    func testRetainedExporterKeepsExactlyItsOriginalValidationOrder() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let destination = fixture.file("exported.txt")
                var order: [String] = []
                let configuration = RetainedFileExporterConfiguration(
                    isPresented: .constant(true),
                    dataProvider: { _ in
                        order.append("serialize")
                        return Data("exported".utf8)
                    },
                    contentType: .plainText,
                    onCompletion: { _ in XCTFail("The writer must not present or complete a dialog.") })

                try configuration.write(to: destination, validate: { order.append("validate") })

                XCTAssertEqual(order, ["validate", "serialize", "validate"])
                XCTAssertEqual(try fixture.bytes(at: destination), Data("exported".utf8))
            }
        }
    }

    func testEditableCodecRoundTripsExactUTF8BytesThroughRealFiles() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let codec = DocumentCodec<ServiceUTF8Document>.editable(ServiceUTF8Document.self)
                let encode = try XCTUnwrap(codec.encode)
                let samples = ["", "  \t\n\r\n\r", "\u{FEFF}e\u{301}😀\r\nline\rend"]
                for (index, text) in samples.enumerated() {
                    let input = fixture.file("input-\(index).txt")
                    let output = fixture.file("output-\(index).txt")
                    let bytes = Data(text.utf8)
                    try bytes.write(to: input)
                    let document = try codec.decode(
                        fixture.service.readRegularFile(at: input, maximumBytes: bytes.count), .utf8PlainText)
                    XCTAssertEqual(document.readContentType, .utf8PlainText)
                    let written = try fixture.service.writeRegularFile(
                        to: output, provideData: { _ in try encode(document, .utf8PlainText) }, validate: {})

                    XCTAssertEqual(written, bytes)
                    XCTAssertEqual(try fixture.bytes(at: output), bytes)
                }
            }
        }
    }

    func testCodecRejectsUndeclaredReadTypesBeforeCallingTheDecoderAndPreservesDecodeErrors() async {
        await MainActor.run { () throws(Never) -> Void in
            let codec = DocumentCodec<ServiceUTF8Document>.viewing(ServiceUTF8Document.self)
            let invalidUTF8 = Data([0xFF])

            XCTAssertThrowsError(try codec.decode(invalidUTF8, .data)) {
                XCTAssertEqual($0 as? DocumentCodecError, .unsupportedReadableContentType(.data))
            }
            XCTAssertThrowsError(try codec.decode(invalidUTF8, .utf8PlainText)) {
                XCTAssertEqual($0 as? DocumentServiceFixtureError, .invalidUTF8)
            }
            XCTAssertNil(codec.encode)
        }
    }

    func testCodecRejectsUndeclaredWriteTypesWithoutCallingTheEncoderOrChangingBytes() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let destination = fixture.file("unchanged.txt")
                let old = Data("old".utf8)
                try old.write(to: destination)
                let probe = DocumentServiceEncodingProbe()
                let document = ServiceUTF8Document(text: "new", probe: probe)
                let encode = try XCTUnwrap(DocumentCodec<ServiceUTF8Document>.editable(ServiceUTF8Document.self).encode)

                XCTAssertThrowsError(
                    try fixture.service.writeRegularFile(
                        to: destination, provideData: { _ in try encode(document, .plainText) }, validate: {})
                ) {
                    XCTAssertEqual($0 as? DocumentCodecError, .unsupportedWritableContentType(.plainText))
                }
                XCTAssertTrue(probe.configurations.isEmpty)
                XCTAssertEqual(try fixture.bytes(at: destination), old)
            }
        }
    }

    func testCodecRejectsEmptyDirectoryAndMixedWrappersBeforeTheAtomicWrite() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let destination = fixture.file("unchanged.txt")
                let old = Data("old".utf8)
                try old.write(to: destination)
                let mixed = FileWrapper(regularFileWithContents: Data("mixed".utf8))
                mixed.fileWrappers = [:]
                let wrappers = [
                    FileWrapper(),
                    FileWrapper(directoryWithFileWrappers: ["child": FileWrapper(regularFileWithContents: Data())]),
                    mixed,
                ]
                let encode = try XCTUnwrap(DocumentCodec<ServiceUTF8Document>.editable(ServiceUTF8Document.self).encode)
                for wrapper in wrappers {
                    let probe = DocumentServiceEncodingProbe()
                    probe.result = .success(wrapper)
                    let document = ServiceUTF8Document(text: "unused", probe: probe)

                    XCTAssertThrowsError(
                        try fixture.service.writeRegularFile(
                            to: destination, provideData: { _ in try encode(document, .utf8PlainText) }, validate: {})
                    ) {
                        XCTAssertEqual($0 as? RetainedFileExportError, .unsupportedFileWrapper)
                    }
                    XCTAssertEqual(probe.configurations.count, 1)
                    XCTAssertNil(probe.configurations.first?.existingFile)
                    XCTAssertEqual(try fixture.bytes(at: destination), old)
                }
                XCTAssertEqual(try fixture.childNames(), ["unchanged.txt"])
            }
        }
    }

    func testCodecPreservesAnApplicationEncodingFailureAndDoesNotReadTheDestinationIntoExistingFile() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let destination = fixture.file("unrelated.txt")
                let old = Data("some other document".utf8)
                try old.write(to: destination)
                let probe = DocumentServiceEncodingProbe()
                probe.result = .failure(DocumentServiceFixtureError.encoding)
                let document = ServiceUTF8Document(text: "new", probe: probe)
                let encode = try XCTUnwrap(DocumentCodec<ServiceUTF8Document>.editable(ServiceUTF8Document.self).encode)

                XCTAssertThrowsError(
                    try fixture.service.writeRegularFile(
                        to: destination, provideData: { _ in try encode(document, .utf8PlainText) }, validate: {})
                ) {
                    XCTAssertEqual($0 as? DocumentServiceFixtureError, .encoding)
                }
                XCTAssertEqual(probe.configurations.count, 1)
                XCTAssertNil(probe.configurations[0].existingFile)
                XCTAssertEqual(probe.configurations[0].contentType, .utf8PlainText)
                XCTAssertEqual(try fixture.bytes(at: destination), old)
            }
        }
    }

    func testViewingCodecRequiresNoFixedWriteConfiguration() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let input = fixture.file("viewed.bin")
                let bytes = Data([0xFF, 0, 1])
                try bytes.write(to: input)
                let codec = DocumentCodec<ServiceViewingDocument>.viewing(ServiceViewingDocument.self)
                let document = try codec.decode(fixture.service.readRegularFile(at: input, maximumBytes: 3), .data)

                XCTAssertEqual(document.bytes, bytes)
                XCTAssertNil(codec.encode)
            }
        }
    }

    func testViewingCodecConstructsTheSuppliedDocumentMetatype() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let input = fixture.file("derived.txt")
                let bytes = Data("derived".utf8)
                try bytes.write(to: input)
                let codec = DocumentCodec<ServiceBaseDocument>.viewing(ServiceDerivedDocument.self)
                let document = try codec.decode(
                    fixture.service.readRegularFile(at: input, maximumBytes: 100), .utf8PlainText)

                XCTAssertTrue(document is ServiceDerivedDocument)
                XCTAssertEqual(document.bytes, bytes)
                XCTAssertNil(codec.encode)
            }
        }
    }

    func testReusableRegularEncoderRequiresNoFixedReadConfiguration() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let destination = fixture.file("write-only.json")
                let probe = DocumentServiceEncodingProbe()
                let document = ServiceWriteOnlyDocument(bytes: Data("{\"ok\":true}".utf8), probe: probe)
                let written = try fixture.service.writeRegularFile(
                    to: destination,
                    provideData: { _ in try fileDocumentExportData(document, contentType: .json) },
                    validate: {})

                XCTAssertEqual(written, document.bytes)
                XCTAssertEqual(try fixture.bytes(at: destination), document.bytes)
                XCTAssertEqual(probe.configurations.count, 1)
                XCTAssertEqual(probe.configurations[0].contentType, .json)
                XCTAssertNil(probe.configurations[0].existingFile)
            }
        }
    }

    func testOpenDialogUsesTypedOutcomeAndForwardsItsOwnerAndFilters() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let url = fixture.file("opened.txt")
                let bytes = Data("open me".utf8)
                try bytes.write(to: url)
                fixture.provider.openOutcome = .selected([url])

                let outcome = fixture.service.chooseOpenURL(types: [.utf8PlainText, .json], owner: .hosted(nil))

                guard case .selected(let selected) = outcome else {
                    return XCTFail("Expected the selected owned file.")
                }
                XCTAssertEqual(selected, url)
                XCTAssertEqual(try fixture.service.readRegularFile(at: selected, maximumBytes: 100), bytes)
                XCTAssertEqual(fixture.provider.openRequests.count, 1)
                let request = fixture.provider.openRequests[0]
                XCTAssertEqual(request.extensions, ["txt", "json"])
                XCTAssertFalse(request.allowsMultiple)
                XCTAssertNil(request.directory)
                guard case .hosted(let handle) = request.owner else { return XCTFail("The hosted owner was lost.") }
                XCTAssertNil(handle)
                XCTAssertTrue(fixture.provider.saveRequests.isEmpty)
            }
        }
    }

    func testSaveDialogUsesTypedOutcomeAndForwardsItsOwnerNameDirectoryAndFilter() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let url = fixture.file("saved.json")
                fixture.provider.saveOutcome = .selected(url)
                let outcome = fixture.service.chooseSaveURL(
                    name: "saved.json", directory: fixture.directory, type: .json, owner: .standalone)

                guard case .selected(let selected) = outcome else { return XCTFail("Expected the selected owned URL.") }
                let bytes = Data("{}".utf8)
                XCTAssertEqual(
                    try fixture.service.writeRegularFile(to: selected, provideData: { _ in bytes }, validate: {}), bytes
                )
                XCTAssertEqual(try fixture.bytes(at: url), bytes)
                XCTAssertEqual(fixture.provider.saveRequests.count, 1)
                let request = fixture.provider.saveRequests[0]
                XCTAssertEqual(request.name, "saved.json")
                XCTAssertEqual(request.directory, fixture.directory)
                XCTAssertEqual(request.extensions, ["json"])
                guard case .standalone = request.owner else { return XCTFail("The standalone owner was lost.") }
                XCTAssertTrue(fixture.provider.openRequests.isEmpty)
            }
        }
    }

    func testDialogCancellationAndFailureStayDistinctWithoutFilesystemEffects() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let openCancelled = fixture.service.chooseOpenURL(types: [.utf8PlainText], owner: .hosted(nil))
                let saveCancelled = fixture.service.chooseSaveURL(
                    name: nil, directory: nil, type: .utf8PlainText, owner: .hosted(nil))
                guard case .cancelled = openCancelled, case .cancelled = saveCancelled else {
                    return XCTFail("Cancellation must remain a distinct terminal outcome.")
                }
                fixture.provider.openOutcome = .failed(FileDialogError.nativeFailure(0x3002))
                fixture.provider.saveOutcome = .failed(FileDialogError.ownerUnavailable)

                assertDocumentDialogFailure(
                    fixture.service.chooseOpenURL(types: [.utf8PlainText], owner: .hosted(nil)),
                    FileDialogError.nativeFailure(0x3002))
                assertDocumentDialogFailure(
                    fixture.service.chooseSaveURL(name: nil, directory: nil, type: .utf8PlainText, owner: .hosted(nil)),
                    FileDialogError.ownerUnavailable)
                XCTAssertTrue(try fixture.childNames().isEmpty)
            }
        }
    }

    func testMalformedDialogSelectionsAreRejectedAndInvalidSaveDirectoryNeverPresents() async throws {
        try await MainActor.run {
            try withDocumentFileFixture { fixture in
                let first = fixture.file("one.txt")
                let second = fixture.file("two.txt")
                for urls in [[], [first, second]] {
                    fixture.provider.openOutcome = .selected(urls)
                    assertDocumentDialogFailure(
                        fixture.service.chooseOpenURL(types: [.utf8PlainText], owner: .standalone),
                        FileDialogError.invalidSelection)
                }
                let remote = try XCTUnwrap(URL(string: "https://example.invalid/document.txt"))
                fixture.provider.openOutcome = .selected([remote])
                fixture.provider.saveOutcome = .selected(remote)
                assertDocumentDialogFailure(
                    fixture.service.chooseOpenURL(types: [.utf8PlainText], owner: .standalone),
                    DocumentFileServiceError.invalidFileURL)
                assertDocumentDialogFailure(
                    fixture.service.chooseSaveURL(name: nil, directory: nil, type: .utf8PlainText, owner: .standalone),
                    DocumentFileServiceError.invalidFileURL)
                let saveCalls = fixture.provider.saveRequests.count
                assertDocumentDialogFailure(
                    fixture.service.chooseSaveURL(
                        name: nil, directory: remote, type: .utf8PlainText, owner: .standalone),
                    DocumentFileServiceError.invalidFileURL)
                XCTAssertEqual(fixture.provider.saveRequests.count, saveCalls)
                XCTAssertTrue(try fixture.childNames().isEmpty)
            }
        }
    }
}

private enum DocumentServiceFixtureError: Error, Equatable {
    case encoding
    case invalidUTF8
    case retired
    case superseded
}

private final class DocumentServiceEncodingProbe {
    var configurations: [FileDocumentWriteConfiguration] = []
    var result: Result<FileWrapper, Error>?
}

private struct ServiceUTF8Document: FileDocument {
    static var readableContentTypes: [UTType] { [.utf8PlainText] }
    let text: String
    let readContentType: UTType?
    var probe: DocumentServiceEncodingProbe?

    init(text: String, probe: DocumentServiceEncodingProbe? = nil) {
        self.text = text
        self.readContentType = nil
        self.probe = probe
    }

    init(configuration: FileDocumentReadConfiguration) throws {
        guard configuration.file.fileWrappers == nil, let bytes = configuration.file.regularFileContents else {
            throw RetainedFileExportError.unsupportedFileWrapper
        }
        let text = String(decoding: bytes, as: UTF8.self)
        guard text.utf8.elementsEqual(bytes) else { throw DocumentServiceFixtureError.invalidUTF8 }
        self.text = text
        self.readContentType = configuration.contentType
    }

    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
        probe?.configurations.append(configuration)
        if let result = probe?.result { return try result.get() }
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct ServiceViewingDocument: FileDocument {
    typealias WriteConfiguration = String
    static var readableContentTypes: [UTType] { [.data] }
    let bytes: Data

    init(configuration: FileDocumentReadConfiguration) throws {
        bytes = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: String) throws -> FileWrapper {
        throw DocumentServiceFixtureError.encoding
    }
}

private struct ServiceWriteOnlyDocument: FileDocument {
    typealias ReadConfiguration = Int
    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.json] }
    let bytes: Data
    var probe: DocumentServiceEncodingProbe?

    init(bytes: Data, probe: DocumentServiceEncodingProbe?) {
        self.bytes = bytes
        self.probe = probe
    }

    init(configuration: Int) throws {
        bytes = Data(String(configuration).utf8)
    }

    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
        probe?.configurations.append(configuration)
        return FileWrapper(regularFileWithContents: bytes)
    }
}

private class ServiceBaseDocument: FileDocument {
    class var readableContentTypes: [UTType] { [.plainText] }
    let bytes: Data

    required init(configuration: FileDocumentReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else {
            throw RetainedFileExportError.unsupportedFileWrapper
        }
        self.bytes = bytes
    }

    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: bytes)
    }
}

private final class ServiceDerivedDocument: ServiceBaseDocument {
    override class var readableContentTypes: [UTType] { [.utf8PlainText] }
}

@MainActor
private final class DocumentServiceDecisionProvider: FileDialogOutcomeProvider {
    struct OpenRequest {
        let extensions: [String]?
        let allowsMultiple: Bool
        let directory: URL?
        let owner: FileDialogOwner
    }

    struct SaveRequest {
        let name: String?
        let extensions: [String]?
        let directory: URL?
        let owner: FileDialogOwner
    }

    var openOutcome: FileDialogOutcome<[URL]> = .cancelled
    var saveOutcome: FileDialogOutcome<URL> = .cancelled
    var openRequests: [OpenRequest] = []
    var saveRequests: [SaveRequest] = []

    func openFileDialogOutcome(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool, defaultDirectory: URL?,
        title: String?, owner: FileDialogOwner
    ) -> FileDialogOutcome<[URL]> {
        openRequests.append(
            OpenRequest(
                extensions: allowedExtensions, allowsMultiple: allowsMultipleSelection, directory: defaultDirectory,
                owner: owner))
        return openOutcome
    }

    func saveFileDialogOutcome(
        defaultFilename: String?, allowedExtensions: [String]?, defaultDirectory: URL?,
        title: String?, owner: FileDialogOwner
    ) -> FileDialogOutcome<URL> {
        saveRequests.append(
            SaveRequest(name: defaultFilename, extensions: allowedExtensions, directory: defaultDirectory, owner: owner)
        )
        return saveOutcome
    }

    func showOpenFileDialog(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool, defaultDirectory: URL?, title: String?
    ) -> [URL] {
        XCTFail("Document sessions must consume the typed outcome adapter.")
        return []
    }

    func showSaveFileDialog(
        defaultFilename: String?, allowedExtensions: [String]?, defaultDirectory: URL?, title: String?
    ) -> URL? {
        XCTFail("Document sessions must consume the typed outcome adapter.")
        return nil
    }
}

@MainActor
private final class DocumentFileFixture {
    static let prefix = "swift-windowsui-document-file-tests-"
    let directory: URL
    let service = LiveDocumentFileService()
    let provider = DocumentServiceDecisionProvider()

    init() throws {
        directory =
            FileManager.default.temporaryDirectory.appendingPathComponent(
                Self.prefix + UUID().uuidString, isDirectory: true
            ).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func bytes(at url: URL) throws -> Data {
        try service.readRegularFile(at: url, maximumBytes: 256 * 1024)
    }

    func childNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func removeOwnedDirectory() throws {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        let owned = directory.standardizedFileURL
        precondition(owned.deletingLastPathComponent() == temporary)
        precondition(owned.lastPathComponent.hasPrefix(Self.prefix))
        try FileManager.default.removeItem(at: owned)
    }
}

@MainActor
private func withDocumentFileFixture(_ body: (DocumentFileFixture) throws -> Void) throws {
    let fixture = try DocumentFileFixture()
    let previous = FileDialogManager.provider
    FileDialogManager.provider = fixture.provider
    defer {
        FileDialogManager.provider = previous
        XCTAssertNoThrow(try fixture.removeOwnedDirectory())
    }
    try body(fixture)
}

private func assertDocumentDialogFailure<Failure: Error & Equatable>(
    _ outcome: FileDialogOutcome<URL>, _ expected: Failure,
    file: StaticString = #filePath, line: UInt = #line
) {
    guard case .failed(let error) = outcome else {
        XCTFail("Expected a typed file dialog failure.", file: file, line: line)
        return
    }
    XCTAssertEqual(error as? Failure, expected, file: file, line: line)
}
