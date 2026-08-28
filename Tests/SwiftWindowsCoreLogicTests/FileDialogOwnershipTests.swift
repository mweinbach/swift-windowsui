import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class FileDialogOwnershipTests: XCTestCase {
    func testInvalidationCannotBeReversedByAnotherPresentationOrReload() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                try fixture.writeOriginalDestination()
                owner.host.invalidateFileDialogRequests()
                owner.host.invalidateFileDialogRequests()

                owner.present()
                owner.host.setContent(Component { _ in owner.node })
                owner.host.processPendingFileDialogs()

                XCTAssertEqual(fixture.provider.requestCount, 0)
                assertNoDialogDelivery(owner)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
            }
        }
    }

    func testOwnerInvalidationDuringModalSuppressesEveryDialogFamily() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    try fixture.writeOriginalDestination()
                    fixture.provider.onDialog = { owner.host.invalidateFileDialogRequests() }

                    owner.present()

                    XCTAssertEqual(fixture.provider.requestCount, 1, "\(kind)")
                    assertNoDialogDelivery(owner)
                    XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                    XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.sourceData)
                }
            }
        }
    }

    func testCancelledModalCannotResetOrCompleteAnInvalidatedOwner() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    try fixture.writeOriginalDestination()
                    fixture.provider.saveResult = nil
                    fixture.provider.openResult = []
                    fixture.provider.onDialog = { owner.host.invalidateFileDialogRequests() }

                    owner.present()

                    XCTAssertEqual(fixture.provider.requestCount, 1, "\(kind)")
                    assertNoDialogDelivery(owner)
                    XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                    XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.sourceData)
                }
            }
        }
    }

    func testScanningExporterBindingCannotStartARemovedImporterSnapshot() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let exporter = fixture.makeOwner(.exporter)
                let importer = fixture.makeOwner(.importer, host: exporter.host)
                importer.node.removeFromParent()
                importer.presented = true
                exporter.node.fileImporterConfiguration = try XCTUnwrap(importer.node.fileImporterConfiguration)
                exporter.onReadPresented = {
                    exporter.node.fileImporterConfiguration = nil
                }

                exporter.host.processPendingFileDialogs()

                XCTAssertGreaterThan(exporter.presentationReadCount, 0)
                XCTAssertFalse(exporter.presented)
                XCTAssertNil(exporter.node.fileImporterConfiguration)
                XCTAssertEqual(importer.presentationReadCount, 0)
                XCTAssertEqual(fixture.provider.requestCount, 0)
                assertNoDialogDelivery(importer)
            }
        }
    }

    func testScanningExporterBindingOnlyStartsTheReplacementImporter() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let exporter = fixture.makeOwner(.exporter)
                let original = fixture.makeOwner(.importer, host: exporter.host)
                let replacement = fixture.makeOwner(.importer, host: exporter.host)
                original.node.removeFromParent()
                replacement.node.removeFromParent()
                original.presented = true
                replacement.presented = true
                exporter.node.fileImporterConfiguration = try XCTUnwrap(original.node.fileImporterConfiguration)
                let replacementConfiguration = try XCTUnwrap(replacement.node.fileImporterConfiguration)
                exporter.onReadPresented = {
                    exporter.node.fileImporterConfiguration = nil
                    exporter.node.fileImporterConfiguration = replacementConfiguration
                }

                exporter.host.processPendingFileDialogs()

                XCTAssertGreaterThan(exporter.presentationReadCount, 0)
                XCTAssertFalse(exporter.presented)
                XCTAssertEqual(original.presentationReadCount, 0)
                assertNoDialogDelivery(original)
                XCTAssertEqual(fixture.provider.requestCount, 1)
                XCTAssertFalse(replacement.presented)
                XCTAssertEqual(replacement.resetCount, 1)
                XCTAssertEqual(replacement.completions.count, 1)
                XCTAssertEqual(try XCTUnwrap(replacement.completions.first).get(), [fixture.picked])
                XCTAssertTrue(exporter.node.parent === exporter.runtime.root)
            }
        }
    }

    func testGetterReplacingItsPresenterServicesTheQueuedReplacementInTheSameCall() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let original = fixture.makeOwner(.exporter)
                let replacement = fixture.makeOwner(.exporter, host: original.host)
                replacement.node.removeFromParent()
                let replacementDestination = fixture.directory.appendingPathComponent("replacement.txt")
                fixture.provider.saveResult = replacementDestination
                try fixture.writeOriginalDestination()
                original.onReadPresented = {
                    original.presented = false
                    original.node.removeFromParent()
                    replacement.presented = true
                    original.runtime.root.addChild(replacement.node)
                    original.host.processPendingFileDialogs()
                }

                original.present()

                XCTAssertEqual(original.presentationReadCount, 1)
                XCTAssertEqual(original.resetCount, 0)
                XCTAssertTrue(original.completions.isEmpty)
                XCTAssertTrue(original.encodedDestinations.isEmpty)
                XCTAssertNil(original.node.parent)
                XCTAssertEqual(fixture.provider.requestCount, 1)
                XCTAssertTrue(replacement.node.parent === original.runtime.root)
                XCTAssertFalse(replacement.presented)
                XCTAssertEqual(replacement.resetCount, 1)
                XCTAssertEqual(replacement.completions.count, 1)
                XCTAssertEqual(try XCTUnwrap(replacement.completions.first).get(), [replacementDestination])
                XCTAssertEqual(replacement.encodedDestinations, [replacementDestination])
                XCTAssertEqual(try Data(contentsOf: replacementDestination), replacement.outputData)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
            }
        }
    }

    func testGetterReinsertingItsOwnPresenterCannotReviveTheSelectedLease() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    try fixture.writeOriginalDestination()
                    owner.onReadPresented = {
                        owner.node.removeFromParent()
                        owner.runtime.root.addChild(owner.node)
                    }

                    owner.present()

                    XCTAssertTrue(owner.node.parent === owner.runtime.root)
                    XCTAssertEqual(owner.presentationReadCount, 1, "\(kind)")
                    XCTAssertEqual(fixture.provider.requestCount, 0)
                    assertNoDialogDelivery(owner)
                    XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                    XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.sourceData)
                }
            }
        }
    }

    func testFalsePresentationGetterCanRequestOnlyOneExtraEmptyScan() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                owner.onReadPresented = {
                    // Bound a broken implementation too, so the regression
                    // reports an excessive scan count instead of hanging.
                    if owner.presentationReadCount < 4 {
                        owner.host.processPendingFileDialogs()
                    }
                }

                owner.host.processPendingFileDialogs()

                XCTAssertEqual(owner.presentationReadCount, 2)
                XCTAssertEqual(fixture.provider.requestCount, 0)
                XCTAssertFalse(owner.presented)
                XCTAssertEqual(owner.resetCount, 0)
                XCTAssertTrue(owner.completions.isEmpty)
                XCTAssertTrue(owner.encodedDestinations.isEmpty)
            }
        }
    }

    func testPresenterRemovalDuringModalSuppressesEveryDialogFamily() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    try fixture.writeOriginalDestination()
                    fixture.provider.onDialog = { owner.node.removeFromParent() }

                    owner.present()

                    XCTAssertEqual(fixture.provider.requestCount, 1, "\(kind)")
                    XCTAssertNil(owner.node.parent)
                    assertNoDialogDelivery(owner)
                    XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                    XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.sourceData)
                }
            }
        }
    }

    func testSamePresenterReinsertedDuringModalCannotReviveItsOldRequest() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    try fixture.writeOriginalDestination()
                    fixture.provider.onDialog = {
                        owner.node.removeFromParent()
                        owner.runtime.root.addChild(owner.node)
                    }

                    owner.present()

                    XCTAssertEqual(fixture.provider.requestCount, 1, "\(kind)")
                    XCTAssertTrue(owner.node.parent === owner.runtime.root)
                    XCTAssertTrue(owner.runtime.root.children.first === owner.node)
                    assertNoDialogDelivery(owner)
                    XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                    XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.sourceData)
                }
            }
        }
    }

    func testRemovedAndReinstalledExporterModifierCannotReviveModalRequest() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                try fixture.writeOriginalDestination()
                let configuration = try XCTUnwrap(owner.node.fileExporterConfiguration)
                fixture.provider.onDialog = {
                    owner.node.fileExporterConfiguration = nil
                    owner.node.fileExporterConfiguration = configuration
                }

                owner.present()

                XCTAssertEqual(fixture.provider.requestCount, 1)
                XCTAssertTrue(owner.node.parent === owner.runtime.root)
                XCTAssertNotNil(owner.node.fileExporterConfiguration)
                assertNoDialogDelivery(owner)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
            }
        }
    }

    func testOwnerInvalidationDuringSerializationPreservesOldDestination() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                try fixture.writeOriginalDestination()
                owner.onEncode = { owner.host.invalidateFileDialogRequests() }

                owner.present()

                XCTAssertEqual(fixture.provider.requestCount, 1)
                assertNoDialogDelivery(owner, serializations: 1)
                XCTAssertEqual(owner.encodedDestinations, [fixture.destination])
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                XCTAssertEqual(try fixture.childNames(), ["destination.txt", "picked.txt", "source.txt"])
            }
        }
    }

    func testPresenterRemovalDuringSerializationPreservesOldDestination() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                try fixture.writeOriginalDestination()
                owner.onEncode = { owner.node.removeFromParent() }

                owner.present()

                XCTAssertNil(owner.node.parent)
                assertNoDialogDelivery(owner, serializations: 1)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
            }
        }
    }

    func testSamePresenterReinsertedDuringSerializationCannotWriteOldRequest() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                try fixture.writeOriginalDestination()
                owner.onEncode = {
                    owner.node.removeFromParent()
                    owner.runtime.root.addChild(owner.node)
                }

                owner.present()

                XCTAssertTrue(owner.node.parent === owner.runtime.root)
                XCTAssertTrue(owner.runtime.root.children.first === owner.node)
                assertNoDialogDelivery(owner, serializations: 1)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
            }
        }
    }

    func testRemovedAndReinstalledExporterModifierCannotWriteAfterSerialization() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                try fixture.writeOriginalDestination()
                let configuration = try XCTUnwrap(owner.node.fileExporterConfiguration)
                owner.onEncode = {
                    owner.node.fileExporterConfiguration = nil
                    owner.node.fileExporterConfiguration = configuration
                }

                owner.present()

                XCTAssertTrue(owner.node.parent === owner.runtime.root)
                XCTAssertNotNil(owner.node.fileExporterConfiguration)
                assertNoDialogDelivery(owner, serializations: 1)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
            }
        }
    }

    func testOwnerInvalidationDuringResetSuppressesCompletionButKeepsFinishedEffects() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    owner.onReset = {
                        owner.host.invalidateFileDialogRequests()
                        owner.host.processPendingFileDialogs()
                    }

                    owner.present()

                    XCTAssertEqual(fixture.provider.requestCount, 1, "\(kind)")
                    XCTAssertEqual(owner.resetCount, 1)
                    XCTAssertFalse(owner.presented)
                    XCTAssertTrue(owner.completions.isEmpty)
                    try fixture.assertFinishedEffects(for: kind, owner: owner)
                }
            }
        }
    }

    func testNormalResetMayRemovePresenterWithoutDiscardingCapturedCompletion() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    owner.onReset = { owner.node.removeFromParent() }

                    owner.present()

                    XCTAssertEqual(fixture.provider.requestCount, 1, "\(kind)")
                    XCTAssertNil(owner.node.parent)
                    XCTAssertFalse(owner.presented)
                    XCTAssertEqual(owner.resetCount, 1)
                    XCTAssertEqual(owner.completions.count, 1)
                    let result = try XCTUnwrap(owner.completions.first)
                    XCTAssertEqual(try result.get(), fixture.selectedURLs(for: kind))
                    XCTAssertEqual(Array(owner.events.suffix(2)), ["reset", "completion"])
                    try fixture.assertFinishedEffects(for: kind, owner: owner)
                }
            }
        }
    }

    func testMoverFinishesFilesystemEffectBeforeResetAndCompletion() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.mover)
                owner.onReset = {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
                    XCTAssertEqual(try? Data(contentsOf: fixture.destination), fixture.sourceData)
                    XCTAssertTrue(owner.completions.isEmpty)
                    owner.events.append("observed-move")
                }

                owner.present()

                XCTAssertEqual(owner.events, ["reset", "observed-move", "completion"])
                XCTAssertEqual(owner.resetCount, 1)
                XCTAssertEqual(owner.completions.count, 1)
                XCTAssertEqual(try XCTUnwrap(owner.completions.first).get(), [fixture.destination])
            }
        }
    }

    func testMoverResetClosingOwnerDoesNotUndoAlreadyFinishedMove() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.mover)
                owner.onReset = {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
                    XCTAssertEqual(try? Data(contentsOf: fixture.destination), fixture.sourceData)
                    owner.host.invalidateFileDialogRequests()
                }

                owner.present()

                XCTAssertEqual(owner.resetCount, 1)
                XCTAssertFalse(owner.presented)
                XCTAssertTrue(owner.completions.isEmpty)
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.sourceData)
            }
        }
    }

    func testRetiringOneHostDoesNotRetireAnotherHost() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let first = fixture.makeOwner(.exporter)
                let second = fixture.makeOwner(.exporter)
                let secondDestination = fixture.directory.appendingPathComponent("second.txt")
                try fixture.writeOriginalDestination()
                fixture.provider.onDialog = { first.host.invalidateFileDialogRequests() }

                first.present()
                fixture.provider.onDialog = nil
                fixture.provider.saveResult = secondDestination
                second.present()

                XCTAssertEqual(fixture.provider.requestCount, 2)
                assertNoDialogDelivery(first)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                XCTAssertEqual(second.resetCount, 1)
                XCTAssertFalse(second.presented)
                XCTAssertEqual(second.encodedDestinations, [secondDestination])
                XCTAssertEqual(second.completions.count, 1)
                XCTAssertEqual(try XCTUnwrap(second.completions.first).get(), [secondDestination])
                XCTAssertEqual(try Data(contentsOf: secondDestination), second.outputData)
            }
        }
    }

    func testQueuedNewPresenterRunsAfterOldPresenterIsRemovedDuringModal() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let first = fixture.makeOwner(.exporter)
                let second = fixture.makeOwner(.exporter, host: first.host)
                let secondDestination = fixture.directory.appendingPathComponent("second.txt")
                try fixture.writeOriginalDestination()
                fixture.provider.onDialog = {
                    guard fixture.provider.requestCount == 1 else { return }
                    first.node.removeFromParent()
                    second.presented = true
                    fixture.provider.saveResult = secondDestination
                    first.host.processPendingFileDialogs()
                }

                first.present()

                XCTAssertEqual(fixture.provider.requestCount, 2)
                XCTAssertNil(first.node.parent)
                assertNoDialogDelivery(first)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                XCTAssertEqual(second.resetCount, 1)
                XCTAssertFalse(second.presented)
                XCTAssertEqual(second.encodedDestinations, [secondDestination])
                XCTAssertEqual(second.completions.count, 1)
                XCTAssertEqual(try XCTUnwrap(second.completions.first).get(), [secondDestination])
                XCTAssertEqual(try Data(contentsOf: secondDestination), second.outputData)
            }
        }
    }

    func testRetiredHostDropsARequestQueuedDuringItsModalDialog() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let first = fixture.makeOwner(.exporter)
                let second = fixture.makeOwner(.exporter, host: first.host)
                let secondDestination = fixture.directory.appendingPathComponent("second.txt")
                try fixture.writeOriginalDestination()
                fixture.provider.onDialog = {
                    second.presented = true
                    fixture.provider.saveResult = secondDestination
                    first.host.processPendingFileDialogs()
                    first.host.invalidateFileDialogRequests()
                }

                first.present()
                first.host.processPendingFileDialogs()

                XCTAssertEqual(fixture.provider.requestCount, 1)
                assertNoDialogDelivery(first)
                assertNoDialogDelivery(second)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                XCTAssertFalse(FileManager.default.fileExists(atPath: secondDestination.path))
            }
        }
    }

    func testCapturedCompletionCanQueueAFreshRequestOnTheSameLivePresenter() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                let firstData = owner.outputData
                let secondData = Data("second export".utf8)
                let secondDestination = fixture.directory.appendingPathComponent("second.txt")
                owner.onCompletion = {
                    guard owner.completions.count == 1 else { return }
                    owner.outputData = secondData
                    owner.presented = true
                    fixture.provider.saveResult = secondDestination
                    owner.host.processPendingFileDialogs()
                }

                owner.present()

                XCTAssertEqual(fixture.provider.requestCount, 2)
                XCTAssertEqual(owner.resetCount, 2)
                XCTAssertFalse(owner.presented)
                XCTAssertEqual(owner.encodedDestinations, [fixture.destination, secondDestination])
                XCTAssertEqual(owner.completions.count, 2)
                XCTAssertEqual(
                    try owner.completions.map { try $0.get() }, [[fixture.destination], [secondDestination]])
                XCTAssertEqual(try Data(contentsOf: fixture.destination), firstData)
                XCTAssertEqual(try Data(contentsOf: secondDestination), secondData)
                XCTAssertEqual(owner.events, ["encode", "reset", "completion", "encode", "reset", "completion"])
            }
        }
    }

    func testNativeFailureReachesOnlyLiveComponentHostOwners() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                for retiresOwner in [false, true] {
                    try withOwnedDialogFixture { fixture in
                        let owner = fixture.makeOwner(kind)
                        try fixture.writeOriginalDestination()
                        var nativeCalls: [String] = []
                        FileDialogManager.provider = Win32FileDialogProvider(
                            openDialog: { _ in
                                nativeCalls.append("open")
                                if retiresOwner { owner.host.invalidateFileDialogRequests() }
                                return false
                            },
                            saveDialog: { _ in
                                nativeCalls.append("save")
                                if retiresOwner { owner.host.invalidateFileDialogRequests() }
                                return false
                            },
                            extendedError: {
                                nativeCalls.append("error")
                                return 0x3002
                            },
                            activeWindow: {
                                nativeCalls.append("active")
                                return nil
                            })

                        owner.present()

                        let expectedDialog = kind == .importer || kind == .importerMulti ? "open" : "save"
                        XCTAssertEqual(nativeCalls, ["active", expectedDialog, "error"], "\(kind), \(retiresOwner)")
                        XCTAssertEqual(fixture.provider.requestCount, 0)
                        XCTAssertTrue(owner.encodedDestinations.isEmpty)
                        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.sourceData)
                        XCTAssertEqual(try fixture.childNames(), ["destination.txt", "picked.txt", "source.txt"])
                        if retiresOwner {
                            assertNoDialogDelivery(owner)
                        } else {
                            XCTAssertFalse(owner.presented)
                            XCTAssertEqual(owner.resetCount, 1)
                            XCTAssertEqual(owner.completions.count, 1)
                            XCTAssertEqual(owner.events, ["reset", "completion"])
                            guard case .failure(let error) = try XCTUnwrap(owner.completions.first) else {
                                XCTFail("A live \(kind) must report the native failure.")
                                return
                            }
                            XCTAssertEqual(error as? FileDialogError, .nativeFailure(0x3002))
                        }
                    }
                }
            }
        }
    }

    func testZeroNativeErrorPreservesEachComponentHostCancellationContract() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    try fixture.writeOriginalDestination()
                    var nativeCalls: [String] = []
                    FileDialogManager.provider = Win32FileDialogProvider(
                        openDialog: { _ in
                            nativeCalls.append("open")
                            return false
                        },
                        saveDialog: { _ in
                            nativeCalls.append("save")
                            return false
                        },
                        extendedError: {
                            nativeCalls.append("error")
                            return 0
                        },
                        activeWindow: {
                            nativeCalls.append("active")
                            return nil
                        })

                    owner.present()

                    let expectedDialog = kind == .importer || kind == .importerMulti ? "open" : "save"
                    XCTAssertEqual(nativeCalls, ["active", expectedDialog, "error"], "\(kind)")
                    XCTAssertEqual(fixture.provider.requestCount, 0)
                    XCTAssertFalse(owner.presented)
                    XCTAssertEqual(owner.resetCount, 1)
                    XCTAssertTrue(owner.encodedDestinations.isEmpty)
                    XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                    XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.sourceData)
                    XCTAssertEqual(try fixture.childNames(), ["destination.txt", "picked.txt", "source.txt"])
                    if kind == .exporter {
                        XCTAssertTrue(owner.completions.isEmpty)
                        XCTAssertEqual(owner.events, ["reset"])
                    } else {
                        XCTAssertEqual(owner.completions.count, 1)
                        XCTAssertEqual(owner.events, ["reset", "completion"])
                        guard case .failure(let error) = try XCTUnwrap(owner.completions.first) else {
                            XCTFail("A cancelled \(kind) must retain its cancellation failure callback.")
                            return
                        }
                        XCTAssertNil(error as? FileDialogError, "Cancellation must not become a native dialog error.")
                    }
                }
            }
        }
    }

    func testDepartingPresenterCannotStartDialogUntilItIsExplicitlyReattached() async throws {
        try await MainActor.run {
            for kind in OwnedDialogKind.allCases {
                try withOwnedDialogFixture { fixture in
                    let owner = fixture.makeOwner(kind)
                    if kind == .exporter { try fixture.writeOriginalDestination() }
                    owner.presented = true
                    var dismantleCount = 0
                    owner.node.onDismantlePlatformView = { departing in
                        dismantleCount += 1
                        XCTAssertTrue(departing === owner.node)
                        XCTAssertTrue(departing.parent === owner.runtime.root)
                        XCTAssertTrue(owner.runtime.root.children.first === departing)
                        owner.host.processPendingFileDialogs()
                    }
                    defer { owner.node.onDismantlePlatformView = nil }
                    XCTAssertEqual(owner.presentationReadCount, 0)

                    owner.runtime.root.replaceChild(at: 0, with: ViewNode())

                    XCTAssertEqual(dismantleCount, 1, "\(kind)")
                    XCTAssertNil(owner.node.parent)
                    XCTAssertEqual(fixture.provider.requestCount, 0)
                    assertNoDialogDelivery(owner)
                    XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.sourceData)
                    if kind == .exporter {
                        XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                    } else {
                        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
                    }

                    // A later explicit attachment starts a new presentation
                    // lifetime; the node itself has not been retired forever.
                    owner.runtime.root.addChild(owner.node)
                    owner.host.processPendingFileDialogs()

                    XCTAssertTrue(owner.node.parent === owner.runtime.root)
                    XCTAssertEqual(dismantleCount, 1)
                    XCTAssertEqual(fixture.provider.requestCount, 1)
                    XCTAssertFalse(owner.presented)
                    XCTAssertEqual(owner.resetCount, 1)
                    XCTAssertEqual(owner.completions.count, 1)
                    XCTAssertEqual(try XCTUnwrap(owner.completions.first).get(), fixture.selectedURLs(for: kind))
                    try fixture.assertFinishedEffects(for: kind, owner: owner)
                }
            }
        }
    }

    func testPreparedModifierRemovalBlocksNewDialogDuringEarlierBranchDismantle() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                try fixture.writeOriginalDestination()
                owner.node.removeFromParent()
                owner.node.nodeTag = "later-presenter"
                let originalConfiguration = try XCTUnwrap(owner.node.fileExporterConfiguration)
                let earlierBranch = ViewNode()
                earlierBranch.nodeTag = "earlier-branch"
                let departingChild = ViewNode()
                earlierBranch.addChild(departingChild)
                owner.runtime.root.addChild(earlierBranch)
                owner.runtime.root.addChild(owner.node)
                owner.presented = true
                var dismantleCount = 0
                departingChild.onDismantlePlatformView = { _ in
                    dismantleCount += 1
                    // The later retained node still reaches the root while
                    // this earlier branch is being reconciled.
                    XCTAssertTrue(owner.node.parent === owner.runtime.root)
                    owner.host.processPendingFileDialogs()
                }
                defer { departingChild.onDismantlePlatformView = nil }
                let nextEarlierBranch = ViewNode()
                nextEarlierBranch.nodeTag = earlierBranch.nodeTag
                let nextPresenter = ViewNode()
                nextPresenter.nodeTag = owner.node.nodeTag
                XCTAssertEqual(owner.presentationReadCount, 0)

                ComponentHost.reconcileChildren(
                    of: owner.runtime.root, oldChildren: owner.runtime.root.children,
                    newNodes: [nextEarlierBranch, nextPresenter])

                XCTAssertEqual(dismantleCount, 1)
                XCTAssertTrue(owner.runtime.root.children.last === owner.node)
                XCTAssertNil(owner.node.fileExporterConfiguration)
                XCTAssertEqual(fixture.provider.requestCount, 0)
                assertNoDialogDelivery(owner)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)

                // The temporary adoption block must not retire a surviving raw
                // slot forever. A later explicit modifier can present anew.
                owner.node.fileExporterConfiguration = originalConfiguration
                owner.host.processPendingFileDialogs()

                XCTAssertTrue(owner.runtime.root.children.last === owner.node)
                XCTAssertEqual(fixture.provider.requestCount, 1)
                XCTAssertEqual(owner.resetCount, 1)
                XCTAssertFalse(owner.presented)
                XCTAssertEqual(owner.completions.count, 1)
                XCTAssertEqual(try XCTUnwrap(owner.completions.first).get(), [fixture.destination])
                XCTAssertEqual(try Data(contentsOf: fixture.destination), owner.outputData)
            }
        }
    }

    func testRevokedCandidatesDoNotResetTheBoundedEmptyScanRetry() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let owner = fixture.makeOwner(.exporter)
                try fixture.writeOriginalDestination()
                let presentation = owner.binding
                var getterReads = 0
                let originalConfiguration = try XCTUnwrap(owner.node.fileExporterConfiguration)
                defer { owner.node.fileExporterConfiguration = originalConfiguration }
                var configuration = originalConfiguration
                configuration.isPresented = Binding(
                    get: {
                        getterReads += 1
                        if getterReads.isMultiple(of: 2) {
                            // Cap a broken loop too, so it fails the count
                            // assertion without keeping the test process busy.
                            if getterReads <= 8 { owner.host.processPendingFileDialogs() }
                            return false
                        }
                        return true
                    },
                    set: { presentation.wrappedValue = $0 })
                owner.node.fileExporterConfiguration = configuration

                owner.present()

                XCTAssertEqual(getterReads, 4)
                XCTAssertEqual(fixture.provider.requestCount, 0)
                assertNoDialogDelivery(owner)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
            }
        }
    }

    func testWindowCloseDuringHostedExporterDialogInvalidatesTheActualOwner() async throws {
        try await MainActor.run {
            try withOwnedDialogFixture { fixture in
                let state = fixture.makeOwner(.exporter)
                let probe = OwnedDocumentEncodingProbe()
                try fixture.writeOriginalDestination()
                let content = Button("Export") { state.presented = true }
                    .fileExporter(
                        isPresented: state.binding,
                        document: OwnedExportDocument(probe: probe),
                        contentType: .plainText,
                        onCompletion: { state.receive($0.map { [$0] }) }
                    )
                    .accessibilityIdentifier("owned-export")
                let configuration = WindowGroupConfiguration(
                    title: "Owned export", size: IntSize(width: 220, height: 140), clearColor: .black,
                    content: [AnyView(content)], windowID: "owned-export")
                let window = Win32Window(title: configuration.title, clientSize: configuration.size)
                window.postsQuitMessageOnDestroy = false
                let host = WinSwiftUIWindowHost(
                    configuration: configuration, platformWindow: window,
                    renderer: FakeRenderBackend(), batchRenderer: nil, startupProbeConfiguration: nil)
                defer { host.windowWillClose(window) }
                var closedCount = 0
                host.onWindowClosed = { _ in closedCount += 1 }
                fixture.provider.onDialog = { [weak host] in host?.windowWillClose(window) }
                XCTAssertNil(window.nativeHandle, "This regression must not create a native test window.")
                let action = try XCTUnwrap(findOwnedExportAction(in: host.hostedRuntime.root))

                action()

                XCTAssertEqual(fixture.provider.requestCount, 1)
                XCTAssertEqual(closedCount, 1)
                XCTAssertEqual(probe.count, 0)
                assertNoDialogDelivery(state)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), fixture.originalData)
                XCTAssertNil(window.nativeHandle)
            }
        }
    }
}

private enum OwnedDialogKind: CaseIterable {
    case exporter
    case importer
    case importerMulti
    case mover
}

private enum OwnedDialogFixtureError: Error {
    case releasedOwner
    case invalidDirectory
}

@MainActor
private final class OwnedDialogProvider: FileDialogProvider {
    var openResult: [URL] = []
    var saveResult: URL?
    var onDialog: (() -> Void)?
    private(set) var openRequestCount = 0
    private(set) var saveRequestCount = 0

    var requestCount: Int { openRequestCount + saveRequestCount }

    func showOpenFileDialog(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool,
        defaultDirectory: URL?, title: String?
    ) -> [URL] {
        openRequestCount += 1
        let result = openResult
        onDialog?()
        return result
    }

    func showSaveFileDialog(
        defaultFilename: String?, allowedExtensions: [String]?,
        defaultDirectory: URL?, title: String?
    ) -> URL? {
        saveRequestCount += 1
        // A callback can queue the next selection; it cannot replace the
        // selected destination belonging to this already-presented dialog.
        let result = saveResult
        onDialog?()
        return result
    }
}

@MainActor
private final class OwnedDialogOwner {
    let host: ComponentHost
    let node = ViewNode()
    var runtime: RetainedViewRuntime { host.runtime }
    var presented = false
    var outputData = Data("new export".utf8)
    var encodedDestinations: [URL] = []
    var presentationReadCount = 0
    var resetCount = 0
    var completions: [Result<[URL], Error>] = []
    var events: [String] = []
    var onReadPresented: (() -> Void)?
    var onEncode: (() -> Void)?
    var onReset: (() -> Void)?
    var onCompletion: (() -> Void)?

    var binding: Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self else { return false }
                self.presentationReadCount += 1
                self.onReadPresented?()
                return self.presented
            },
            set: { [weak self] value in
                guard let self else { return }
                self.presented = value
                if !value {
                    self.resetCount += 1
                    self.events.append("reset")
                    self.onReset?()
                }
            })
    }

    init(kind: OwnedDialogKind, source: URL, host: ComponentHost?) {
        self.host = host ?? ComponentHost(runtime: RetainedViewRuntime(root: ViewNode()))
        switch kind {
        case .exporter:
            node.fileExporterConfiguration = RetainedFileExporterConfiguration(
                isPresented: binding,
                dataProvider: { [weak self] destination in
                    guard let self else { throw OwnedDialogFixtureError.releasedOwner }
                    self.encodedDestinations.append(destination)
                    self.events.append("encode")
                    self.onEncode?()
                    return self.outputData
                },
                contentType: .plainText, defaultFilename: "destination.txt",
                onCompletion: { [weak self] in self?.receive($0.map { [$0] }) })
        case .importer:
            node.fileImporterConfiguration = RetainedFileImporterConfiguration(
                isPresented: binding, allowedContentTypes: [.plainText],
                onCompletion: { [weak self] in self?.receive($0.map { [$0] }) })
        case .importerMulti:
            node.fileImporterMultiConfiguration = RetainedFileImporterMultiConfiguration(
                isPresented: binding, allowedContentTypes: [.plainText], allowsMultipleSelection: true,
                onCompletion: { [weak self] in self?.receive($0) })
        case .mover:
            node.fileMoverConfiguration = RetainedFileMoverConfiguration(
                isPresented: binding, file: source,
                onCompletion: { [weak self] in self?.receive($0.map { [$0] }) })
        }
        runtime.root.addChild(node)
    }

    func receive(_ result: Result<[URL], Error>) {
        completions.append(result)
        events.append("completion")
        onCompletion?()
    }

    func present() {
        presented = true
        host.processPendingFileDialogs()
    }

    func cleanUp() {
        onReadPresented = nil
        onEncode = nil
        onReset = nil
        onCompletion = nil
        host.invalidateFileDialogRequests()
        node.removeFromParent()
        host.setComponents { [] }
    }
}

@MainActor
private final class OwnedDialogFixture {
    let directory: URL
    let source: URL
    let picked: URL
    let destination: URL
    let provider = OwnedDialogProvider()
    let originalData = Data("original destination".utf8)
    let sourceData = Data("move source".utf8)
    private var owners: [OwnedDialogOwner] = []

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-windowsui-dialog-ownership-\(UUID().uuidString)", isDirectory: true)
        source = directory.appendingPathComponent("source.txt")
        picked = directory.appendingPathComponent("picked.txt")
        destination = directory.appendingPathComponent("destination.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try sourceData.write(to: source)
            try Data("picked file".utf8).write(to: picked)
        } catch {
            try? removeOwnedDirectory()
            throw error
        }
        provider.openResult = [picked, source]
        provider.saveResult = destination
    }

    func makeOwner(_ kind: OwnedDialogKind, host: ComponentHost? = nil) -> OwnedDialogOwner {
        let owner = OwnedDialogOwner(kind: kind, source: source, host: host)
        owners.append(owner)
        return owner
    }

    func writeOriginalDestination() throws {
        try originalData.write(to: destination)
    }

    func childNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func selectedURLs(for kind: OwnedDialogKind) -> [URL] {
        switch kind {
        case .exporter, .mover: [destination]
        case .importer: [picked]
        case .importerMulti: [picked, source]
        }
    }

    func assertFinishedEffects(for kind: OwnedDialogKind, owner: OwnedDialogOwner) throws {
        switch kind {
        case .exporter:
            XCTAssertEqual(owner.encodedDestinations, [destination])
            XCTAssertEqual(try Data(contentsOf: destination), owner.outputData)
            XCTAssertEqual(try Data(contentsOf: source), sourceData)
        case .mover:
            XCTAssertTrue(owner.encodedDestinations.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try Data(contentsOf: destination), sourceData)
        case .importer, .importerMulti:
            XCTAssertTrue(owner.encodedDestinations.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: source), sourceData)
        }
    }

    func cleanUp() throws {
        provider.onDialog = nil
        for owner in owners { owner.cleanUp() }
        owners.removeAll()
        try removeOwnedDirectory()
    }

    private func removeOwnedDirectory() throws {
        guard
            directory.deletingLastPathComponent().standardizedFileURL
                == FileManager.default.temporaryDirectory.standardizedFileURL,
            directory.lastPathComponent.hasPrefix("swift-windowsui-dialog-ownership-")
        else { throw OwnedDialogFixtureError.invalidDirectory }
        try FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func withOwnedDialogFixture(_ body: (OwnedDialogFixture) throws -> Void) throws {
    let fixture = try OwnedDialogFixture()
    let previous = FileDialogManager.provider
    FileDialogManager.provider = fixture.provider
    defer {
        FileDialogManager.provider = previous
        do {
            try fixture.cleanUp()
        } catch {
            XCTFail("Failed to remove the owned dialog fixture: \(error)")
        }
    }
    try body(fixture)
}

@MainActor
private func assertNoDialogDelivery(
    _ owner: OwnedDialogOwner, serializations: Int = 0,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertTrue(owner.presented, "A stale request must not reset its presentation binding.", file: file, line: line)
    XCTAssertEqual(owner.resetCount, 0, file: file, line: line)
    XCTAssertTrue(owner.completions.isEmpty, file: file, line: line)
    XCTAssertEqual(owner.encodedDestinations.count, serializations, file: file, line: line)
}

private final class OwnedDocumentEncodingProbe {
    var count = 0
}

private struct OwnedExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var probe: OwnedDocumentEncodingProbe?

    init(probe: OwnedDocumentEncodingProbe) {
        self.probe = probe
    }

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        probe?.count += 1
        return FileWrapper(regularFileWithContents: Data("hosted export".utf8))
    }
}

@MainActor
private func findOwnedExportAction(in node: ViewNode) -> (() -> Void)? {
    if node.accessibilityIdentifier == "owned-export", let action = node.onActivate {
        return action
    }
    for child in node.children {
        if let action = findOwnedExportAction(in: child) { return action }
    }
    return nil
}
