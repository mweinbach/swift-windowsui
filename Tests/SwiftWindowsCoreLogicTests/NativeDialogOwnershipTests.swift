import Foundation
import SwiftWindowsCore
import Synchronization
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Every command executes against a synthetic context and an explicitly injected
/// executor. No test creates an HWND, opens a dialog, or writes a selected file.
@MainActor
final class NativeDialogOwnershipTests: XCTestCase {
    func testCommandUsesCapturedInputsAndUnwindsModalScopeBeforeReply() async throws {
        let key = NativeWindowKey()
        let picked = URL(fileURLWithPath: "C:/dialog-fixture/picked.txt")
        let directory = picked.deletingLastPathComponent()
        let probe = NativeDialogOwnershipProbe(response: .selectedFiles([picked]))
        let context = NativeDialogOwnershipContext(windowKey: key, probe: probe)
        var extensions = ["txt"]
        let command = NativeDialogCommand(
            windowKey: key,
            request: .openFile(
                allowedExtensions: extensions, allowsMultipleSelection: true,
                defaultDirectory: directory, title: "Captured title"),
            executor: NativeDialogExecutor { probe.perform($0, handle: $1) },
            reply: NativeWindowReply { probe.receive($0) })
        extensions.append("png")

        try command.execute(in: context)
        command.reject(.closed)

        XCTAssertEqual(probe.events, ["modal-enter", "execute", "modal-exit", "reply"])
        XCTAssertEqual(context.modalDepth, 0)
        XCTAssertEqual(probe.handles, [try XCTUnwrap(context.surface.descriptor.windowHandle)])
        XCTAssertEqual(probe.replies.count, 1, "A late rejection cannot replace the actual result.")
        guard case .success(.selectedFiles(let urls)) = try XCTUnwrap(probe.replies.first) else {
            return XCTFail("Expected the executor's selected files.")
        }
        XCTAssertEqual(urls, [picked])
        guard
            case .openFile(let capturedExtensions, let multiple, let capturedDirectory, let title) =
                try XCTUnwrap(probe.requests.first)
        else { return XCTFail("Expected the copied open request.") }
        XCTAssertEqual(capturedExtensions, ["txt"])
        XCTAssertTrue(multiple)
        XCTAssertEqual(capturedDirectory, directory)
        XCTAssertEqual(title, "Captured title")
    }

    func testCommandRejectsWrongLifetimeAndMissingOwnerWithoutRunningExecutor() async throws {
        for missingOwner in [false, true] {
            let key = NativeWindowKey()
            let contextKey = missingOwner ? key : NativeWindowKey(windowID: key.windowID)
            let probe = NativeDialogOwnershipProbe(response: .cancelled)
            let context = NativeDialogOwnershipContext(
                windowKey: contextKey, hasWindow: !missingOwner, probe: probe)
            let command = NativeDialogCommand(
                windowKey: key,
                request: .saveFile(
                    defaultFilename: "fixture.txt", allowedExtensions: ["txt"],
                    defaultDirectory: nil, title: nil),
                executor: NativeDialogExecutor { probe.perform($0, handle: $1) },
                reply: NativeWindowReply { probe.receive($0) })

            try command.execute(in: context)

            XCTAssertTrue(probe.requests.isEmpty)
            XCTAssertEqual(probe.events, ["reply"])
            XCTAssertEqual(context.modalDepth, 0)
            let reply = try XCTUnwrap(probe.replies.first)
            if missingOwner {
                guard case .success(.failed(.ownerUnavailable)) = reply else {
                    return XCTFail("Missing ownership must be a failure, not cancellation.")
                }
            } else {
                guard case .failure(.staleWindow) = reply else {
                    return XCTFail("A reused window identity cannot authorize another lifetime.")
                }
            }
        }
    }

    func testSessionRevocationPinsPayloadUntilTerminalReplyAndConsumesItOnce() async throws {
        let driver = NativeDialogOwnershipDriver(response: .cancelled)
        let delivered = NativeDialogOwnershipSignal()
        let released = NativeDialogOwnershipSignal()
        var payload: NativeDialogOwnershipPayload? = NativeDialogOwnershipPayload(released: released)
        weak var retainedPayload = payload
        var responses: [NativeDialogResponse] = []
        driver.session.request(
            .openFile(allowedExtensions: nil, allowsMultipleSelection: false, defaultDirectory: nil, title: nil)
        ) { [payload] response in
            withExtendedLifetime(payload) { responses.append(response) }
            delivered.signal()
        }
        payload = nil
        driver.session.invalidate()

        XCTAssertTrue(driver.session.hasPendingRequests)
        XCTAssertNotNil(retainedPayload)
        XCTAssertTrue(responses.isEmpty)
        var refusedInline = false
        driver.session.request(.color(initial: .black)) { response in
            guard case .revoked = response else { return XCTFail("A retired session cannot admit another request.") }
            refusedInline = true
        }
        XCTAssertTrue(refusedInline)
        XCTAssertEqual(driver.sink.submissionCount, 1)

        let command = try driver.performNext()
        command.reject(.postFailed(code: 9))
        await delivered.wait()
        await released.wait()

        XCTAssertFalse(driver.session.hasPendingRequests)
        XCTAssertNil(retainedPayload)
        XCTAssertEqual(responses.count, 1)
        XCTAssertNil(driver.session.lastFailure)
        guard case .revoked = try XCTUnwrap(responses.first) else {
            return XCTFail("Revocation must not be reported as a cancelled native dialog.")
        }
    }

    func testSessionFinishesCallbackAndCaptureCleanupBeforeAdvancingItsFIFO() async throws {
        for retiresSecond in [false, true] {
            let driver = NativeDialogOwnershipDriver(response: .cancelled)
            let firstReleased = NativeDialogOwnershipSignal()
            let finished = NativeDialogOwnershipSignal()
            var firstPayload: NativeDialogOwnershipPayload? = NativeDialogOwnershipPayload(released: firstReleased)
            weak var retainedFirstPayload = firstPayload
            var secondIsCurrent = true
            var secondChecks = 0
            var events: [String] = []
            var responses: [String: NativeDialogResponse] = [:]
            driver.session.request(
                .color(initial: .black),
                isCurrent: { [firstPayload] in withExtendedLifetime(firstPayload) { true } },
                completion: { [firstPayload] response in
                    withExtendedLifetime(firstPayload) {
                        responses["first"] = response
                        events.append("first-begin")
                        secondIsCurrent = !retiresSecond
                        driver.session.request(
                            .color(initial: .clear),
                            isCurrent: {
                                XCTAssertNil(retainedFirstPayload)
                                XCTAssertEqual(events.last, "second-reply")
                                events.append("third-check")
                                return true
                            },
                            completion: { response in
                                responses["third"] = response
                                events.append("third-reply")
                                finished.signal()
                            })
                        XCTAssertEqual(
                            driver.sink.submissionCount, 1, "A reentrant request must join the existing queue.")
                        XCTAssertEqual(secondChecks, 0, "The next caller cannot be read inside this completion.")
                        events.append("first-end")
                    }
                })
            firstPayload = nil
            driver.session.request(
                .color(initial: .white),
                isCurrent: {
                    secondChecks += 1
                    XCTAssertNil(
                        retainedFirstPayload, "Release both the prior completion and predicate before advancing.")
                    XCTAssertEqual(events.last, "first-end")
                    events.append("second-check")
                    return secondIsCurrent
                },
                completion: { response in
                    responses["second"] = response
                    events.append("second-reply")
                    XCTAssertEqual(driver.sink.submissionCount, retiresSecond ? 1 : 2)
                })
            XCTAssertEqual(driver.sink.submissionCount, 1)
            XCTAssertEqual(secondChecks, 0)
            XCTAssertNotNil(retainedFirstPayload)

            try driver.performNext()
            await driver.sink.waitForSubmissionCount(2)
            await firstReleased.wait()
            XCTAssertNil(retainedFirstPayload)
            XCTAssertEqual(secondChecks, 1)
            try driver.performNext()
            if !retiresSecond {
                await driver.sink.waitForSubmissionCount(3)
                try driver.performNext()
            }
            await finished.wait()

            XCTAssertEqual(
                events, ["first-begin", "first-end", "second-check", "second-reply", "third-check", "third-reply"])
            let executedColors = driver.probe.requests.compactMap { request -> Color? in
                guard case .color(let initial) = request else { return nil }
                return initial
            }
            XCTAssertEqual(executedColors, retiresSecond ? [.black, .clear] : [.black, .white, .clear])
            XCTAssertEqual(driver.probe.requests.count, retiresSecond ? 2 : 3)
            XCTAssertEqual(driver.sink.submissionCount, retiresSecond ? 2 : 3)
            XCTAssertFalse(driver.session.hasPendingRequests)
            XCTAssertNil(driver.session.lastFailure)
            guard case .cancelled = try XCTUnwrap(responses["first"]),
                case .cancelled = try XCTUnwrap(responses["third"])
            else { return XCTFail("The actual native cancellations must remain cancellations.") }
            let secondResponse = try XCTUnwrap(responses["second"])
            if retiresSecond {
                guard case .revoked = secondResponse else {
                    return XCTFail("A stale queued caller must be revoked without opening another dialog.")
                }
            } else {
                guard case .cancelled = secondResponse else { return XCTFail("The live second request must run.") }
            }
        }
    }

    func testInvalidationRetiresQueuedCapturesAfterTeardownButPinsSubmittedCaptureUntilReply() async throws {
        let driver = NativeDialogOwnershipDriver(response: .cancelled)
        let activeDelivered = NativeDialogOwnershipSignal()
        let activeReleased = NativeDialogOwnershipSignal()
        let queuedDelivered = NativeDialogOwnershipSignal()
        let queuedReleased = NativeDialogOwnershipSignal()
        var activePayload: NativeDialogOwnershipPayload? = NativeDialogOwnershipPayload(released: activeReleased)
        var queuedPayload: NativeDialogOwnershipPayload? = NativeDialogOwnershipPayload(released: queuedReleased)
        weak var retainedActive = activePayload
        weak var retainedQueued = queuedPayload
        var activeChecks = 0
        var queuedChecks = 0
        var events: [String] = []
        var activeResponse: NativeDialogResponse?
        var queuedResponse: NativeDialogResponse?
        driver.session.request(
            .color(initial: .black),
            isCurrent: { [activePayload] in
                withExtendedLifetime(activePayload) {
                    activeChecks += 1
                    return true
                }
            },
            completion: { [activePayload] response in
                withExtendedLifetime(activePayload) {
                    activeResponse = response
                    events.append("active-reply")
                    activeDelivered.signal()
                }
            })
        driver.session.request(
            .color(initial: .white),
            isCurrent: { [queuedPayload] in
                withExtendedLifetime(queuedPayload) {
                    queuedChecks += 1
                    return true
                }
            },
            completion: { [queuedPayload] response in
                withExtendedLifetime(queuedPayload) {
                    queuedResponse = response
                    XCTAssertEqual(events, ["teardown-finished"])
                    XCTAssertNotNil(retainedActive)
                    events.append("queued-reply")
                    queuedDelivered.signal()
                }
            })
        activePayload = nil
        queuedPayload = nil
        XCTAssertEqual(activeChecks, 1)
        XCTAssertEqual(queuedChecks, 0)
        XCTAssertEqual(driver.sink.submissionCount, 1)

        driver.session.invalidate()
        XCTAssertNotNil(retainedActive)
        XCTAssertNotNil(retainedQueued, "Invalidation must not release queued captures inside synchronous teardown.")
        XCTAssertNil(activeResponse)
        XCTAssertNil(queuedResponse)
        events.append("teardown-finished")
        await queuedDelivered.wait()
        await queuedReleased.wait()

        XCTAssertNil(retainedQueued)
        XCTAssertNotNil(retainedActive)
        XCTAssertTrue(driver.session.hasPendingRequests)
        XCTAssertNil(activeResponse)
        XCTAssertEqual(activeChecks, 1)
        XCTAssertEqual(queuedChecks, 0, "An invalid window cannot read queued caller state.")
        XCTAssertEqual(driver.sink.submissionCount, 1)
        XCTAssertTrue(driver.probe.requests.isEmpty)
        guard case .revoked = try XCTUnwrap(queuedResponse) else {
            return XCTFail("An unsubmitted request is revoked, not cancelled or failed.")
        }

        try driver.performNext()
        await activeDelivered.wait()
        await activeReleased.wait()

        XCTAssertEqual(events, ["teardown-finished", "queued-reply", "active-reply"])
        XCTAssertNil(retainedActive)
        XCTAssertFalse(driver.session.hasPendingRequests)
        XCTAssertEqual(driver.probe.requests.count, 1)
        XCTAssertEqual(driver.sink.submissionCount, 1)
        XCTAssertEqual(activeChecks, 1)
        XCTAssertEqual(queuedChecks, 0)
        XCTAssertNil(driver.session.lastFailure)
        guard case .revoked = try XCTUnwrap(activeResponse) else {
            return XCTFail("Only the actual reply may release the submitted request's revoked completion.")
        }
    }

    func testInvalidationInsideAdmissionPredicateDefersRetirementUntilAfterCallout() async throws {
        let driver = NativeDialogOwnershipDriver(response: .cancelled)
        let delivered = NativeDialogOwnershipSignal()
        let released = NativeDialogOwnershipSignal()
        var payload: NativeDialogOwnershipPayload? = NativeDialogOwnershipPayload(released: released)
        weak var retainedPayload = payload
        var events: [String] = []
        var response: NativeDialogResponse?
        driver.session.request(
            .color(initial: .black),
            isCurrent: { [payload] in
                withExtendedLifetime(payload) {
                    events.append("predicate")
                    driver.session.invalidate()
                    return true
                }
            },
            completion: { [payload] value in
                withExtendedLifetime(payload) {
                    XCTAssertEqual(events, ["predicate", "teardown-finished"])
                    response = value
                    delivered.signal()
                }
            })
        payload = nil
        XCTAssertNotNil(retainedPayload)
        XCTAssertNil(response, "An invalidating predicate must not receive revocation on the same actor turn.")
        XCTAssertFalse(driver.session.isValid)
        XCTAssertTrue(driver.session.hasPendingRequests)
        XCTAssertEqual(driver.sink.submissionCount, 0)
        events.append("teardown-finished")

        await delivered.wait()
        await released.wait()

        XCTAssertNil(retainedPayload)
        XCTAssertFalse(driver.session.hasPendingRequests)
        XCTAssertEqual(driver.sink.submissionCount, 0)
        XCTAssertTrue(driver.probe.requests.isEmpty)
        guard case .revoked = try XCTUnwrap(response) else {
            return XCTFail("Invalidation inside admission must revoke the unsubmitted request.")
        }
    }

    func testMixedRecycleRequestRejectsEveryItemBeforeEnteringNativeExecutor() async throws {
        let valid = URL(fileURLWithPath: "C:/dialog-fixture/valid.txt")
        let nonFile = try XCTUnwrap(URL(string: "https://example.invalid/not-a-local-file"))
        let embeddedNull = try XCTUnwrap(URL(string: "file:///C:/dialog-fixture/bad%00.txt"))
        let remoteAuthority = try XCTUnwrap(URL(string: "file://other-host/share/remote.txt"))
        for urls in [[], [valid, nonFile], [valid, embeddedNull], [valid, remoteAuthority]] {
            let key = NativeWindowKey()
            let probe = NativeDialogOwnershipProbe(response: .recycled)
            let context = NativeDialogOwnershipContext(windowKey: key, probe: probe)
            let command = NativeDialogCommand(
                windowKey: key, request: .recycleFiles(urls),
                executor: NativeDialogExecutor { probe.perform($0, handle: $1) },
                reply: NativeWindowReply { probe.receive($0) })

            try command.execute(in: context)

            XCTAssertTrue(probe.requests.isEmpty, "Validation cannot recycle only the valid subset.")
            XCTAssertEqual(probe.events, ["reply"])
            XCTAssertEqual(context.modalDepth, 0)
            guard case .success(.failed(.invalidFileURL)) = try XCTUnwrap(probe.replies.first) else {
                return XCTFail("An invalid recycle request must fail explicitly, never report success or cancellation.")
            }
        }
    }

    func testManagerKeepsCancellationNativeFailureAndTransportFailureDistinct() async throws {
        let previous = FileDialogManager.provider
        FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
        defer { FileDialogManager.provider = previous }
        let cases: [(NativeDialogResponse, NativeDialogOwnershipExpectedOutcome)] = [
            (.cancelled, .cancelled),
            (.failed(.native(operation: "GetOpenFileNameW", code: 0x3002)), .fileFailure(.nativeFailure(0x3002))),
            (.selectedFiles([]), .fileFailure(.invalidSelection)),
            (.selectedColor(.black), .nativeFailure(.unexpectedResult)),
        ]
        for (response, expected) in cases {
            let driver = NativeDialogOwnershipDriver(response: response)
            let delivered = NativeDialogOwnershipSignal()
            var received: DialogRequestOutcome<[URL]>?
            FileDialogManager.requestOpenFileDialog(nativeSession: driver.session) {
                received = $0
                delivered.signal()
            }
            XCTAssertNil(received, "Admission is not a completed selection.")
            XCTAssertTrue(driver.session.hasPendingRequests)

            try driver.performNext()
            await delivered.wait()

            XCTAssertFalse(driver.session.hasPendingRequests)
            assertOutcome(try XCTUnwrap(received), equals: expected)
        }

        let rejected = NativeDialogOwnershipDriver(response: .cancelled, rejection: .postFailed(code: 7))
        let delivered = NativeDialogOwnershipSignal()
        var outcomes: [DialogRequestOutcome<[URL]>] = []
        FileDialogManager.requestOpenFileDialog(nativeSession: rejected.session) {
            outcomes.append($0)
            delivered.signal()
        }
        await delivered.wait()

        XCTAssertEqual(outcomes.count, 1, "Sink rejection and submission rejection share one checked reply.")
        assertOutcome(
            try XCTUnwrap(outcomes.first), equals: .nativeFailure(.transport(.postFailed(code: 7))))
        XCTAssertEqual(rejected.session.lastFailure, .transport(.postFailed(code: 7)))
        XCTAssertFalse(rejected.session.hasPendingRequests)
        XCTAssertTrue(rejected.probe.requests.isEmpty)
        XCTAssertEqual(rejected.sink.queuedCount, 0)
    }

    func testComponentHostKeepsDeferredGateThroughCompletionAndRequeuesFreshRequest() async throws {
        let previous = FileDialogManager.provider
        FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
        defer { FileDialogManager.provider = previous }
        let firstURL = URL(fileURLWithPath: "C:/dialog-fixture/first.txt")
        let secondURL = URL(fileURLWithPath: "C:/dialog-fixture/second.txt")
        let driver = NativeDialogOwnershipDriver(response: .selectedFiles([firstURL]))
        let owner = NativeDialogOwnershipPresenter(driver: driver)
        defer { owner.cleanUp() }
        let finished = NativeDialogOwnershipSignal()
        owner.onCompletion = {
            if owner.results.count == 1 {
                owner.events.append("requeue-begin")
                owner.presented = true
                owner.host.processPendingFileDialogs()
                XCTAssertEqual(driver.sink.submissionCount, 1, "Completion must finish before the next selection.")
                owner.events.append("requeue-end")
            } else {
                finished.signal()
            }
        }
        owner.present()
        owner.host.processPendingFileDialogs()
        owner.host.processPendingFileDialogs()
        XCTAssertTrue(owner.presented)
        XCTAssertEqual(owner.resets, 0)
        XCTAssertTrue(owner.results.isEmpty)
        XCTAssertEqual(driver.sink.submissionCount, 1)

        let firstCommand = try driver.performNext()
        await driver.sink.waitForSubmissionCount(2)
        XCTAssertEqual(owner.events, ["reset", "completion", "requeue-begin", "requeue-end"])
        XCTAssertEqual(owner.resets, 1)
        XCTAssertTrue(owner.presented)
        XCTAssertTrue(driver.session.hasPendingRequests)
        firstCommand.reject(.closed)
        driver.probe.response = .selectedFiles([secondURL])
        try driver.performNext()
        await finished.wait()

        XCTAssertEqual(try owner.results.map { try $0.get() }, [firstURL, secondURL])
        XCTAssertEqual(owner.resets, 2)
        XCTAssertFalse(owner.presented)
        XCTAssertEqual(driver.sink.submissionCount, 2)
        XCTAssertFalse(driver.session.hasPendingRequests)
    }

    func testComponentHostAndDirectRequestsShareFIFOThroughResetCompletionAndCaptureRelease() async throws {
        let previous = FileDialogManager.provider
        FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
        defer { FileDialogManager.provider = previous }
        let picked = URL(fileURLWithPath: "C:/dialog-fixture/before-direct-color.txt")
        let chosen = Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let driver = NativeDialogOwnershipDriver(response: .selectedFiles([picked]))
        let owner = NativeDialogOwnershipPresenter(driver: driver)
        defer { owner.cleanUp() }
        let finished = NativeDialogOwnershipSignal()
        var events: [String] = []
        var directResponse: NativeDialogResponse?
        owner.onReset = {
            events.append("reset-begin")
            XCTAssertEqual(driver.sink.submissionCount, 1)
            owner.removePresenter()
            XCTAssertNotNil(owner.payload)
            events.append("reset-end")
        }
        owner.onCompletion = {
            events.append("completion-begin")
            XCTAssertEqual(driver.sink.submissionCount, 1, "The direct request cannot run inside retained completion.")
            XCTAssertNotNil(owner.payload)
            events.append("completion-end")
        }
        owner.present()
        driver.session.request(
            .color(initial: .black),
            isCurrent: {
                XCTAssertEqual(events, ["reset-begin", "reset-end", "completion-begin", "completion-end"])
                XCTAssertNil(owner.payload, "Retained configuration captures must unwind before direct dispatch.")
                events.append("direct-check")
                return true
            },
            completion: { response in
                directResponse = response
                events.append("direct-reply")
                finished.signal()
            })
        XCTAssertEqual(driver.sink.submissionCount, 1)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(owner.results.isEmpty)

        try driver.performNext()
        await driver.sink.waitForSubmissionCount(2)
        await owner.payloadReleased.wait()

        XCTAssertEqual(owner.resets, 1)
        XCTAssertEqual(try owner.results.map { try $0.get() }, [picked])
        XCTAssertFalse(owner.presented)
        XCTAssertTrue(driver.session.hasPendingRequests)
        XCTAssertNil(directResponse)
        driver.probe.response = .selectedColor(chosen)
        try driver.performNext()
        await finished.wait()

        XCTAssertEqual(
            events, ["reset-begin", "reset-end", "completion-begin", "completion-end", "direct-check", "direct-reply"])
        XCTAssertEqual(driver.sink.submissionCount, 2)
        XCTAssertEqual(driver.probe.requests.count, 2)
        XCTAssertFalse(driver.session.hasPendingRequests)
        guard case .selectedColor(let selected) = try XCTUnwrap(directResponse) else {
            return XCTFail("The direct request must receive its own color selection.")
        }
        XCTAssertEqual(selected, chosen)
    }

    func testComponentHostRetirementDropsQueuedWorkButPinsPendingConfiguration() async throws {
        let previous = FileDialogManager.provider
        FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
        defer { FileDialogManager.provider = previous }
        for kind in NativeDialogOwnershipPresenter.Kind.allCases {
            let driver = NativeDialogOwnershipDriver(
                response: .selectedFiles([URL(fileURLWithPath: "C:/dialog-fixture/retired.txt")]))
            let owner = NativeDialogOwnershipPresenter(driver: driver, kind: kind)
            defer { owner.cleanUp() }
            owner.present()
            owner.host.processPendingFileDialogs()
            owner.host.invalidateFileDialogRequests()
            driver.session.invalidate()
            owner.removePresenter()

            XCTAssertTrue(driver.session.hasPendingRequests)
            XCTAssertNotNil(owner.payload, "Revocation must not release an outstanding configuration.")
            XCTAssertEqual(owner.resets, 0)
            XCTAssertTrue(owner.results.isEmpty)
            try driver.performNext()
            await owner.payloadReleased.wait()
            owner.host.processPendingFileDialogs()

            XCTAssertNil(owner.payload)
            XCTAssertFalse(driver.session.hasPendingRequests)
            XCTAssertTrue(owner.presented)
            XCTAssertEqual(owner.resets, 0)
            XCTAssertTrue(owner.results.isEmpty)
            XCTAssertEqual(owner.encodes, 0)
            XCTAssertEqual(driver.sink.submissionCount, 1)
        }
    }

    func testReinsertedPresenterCannotConsumeOldSelectionButCanPresentAgain() async throws {
        let previous = FileDialogManager.provider
        FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
        defer { FileDialogManager.provider = previous }
        let oldURL = URL(fileURLWithPath: "C:/dialog-fixture/old.txt")
        let newURL = URL(fileURLWithPath: "C:/dialog-fixture/new.txt")
        let driver = NativeDialogOwnershipDriver(response: .selectedFiles([oldURL]))
        let owner = NativeDialogOwnershipPresenter(driver: driver)
        defer { owner.cleanUp() }
        let finished = NativeDialogOwnershipSignal()
        owner.onCompletion = { finished.signal() }
        owner.present()
        owner.node.removeFromParent()
        owner.host.runtime.root.addChild(owner.node)
        owner.host.processPendingFileDialogs()
        XCTAssertEqual(driver.sink.submissionCount, 1)

        try driver.performNext()
        await driver.sink.waitForSubmissionCount(2)

        XCTAssertTrue(owner.results.isEmpty)
        XCTAssertEqual(owner.resets, 0)
        XCTAssertTrue(owner.presented)
        driver.probe.response = .selectedFiles([newURL])
        try driver.performNext()
        await finished.wait()

        XCTAssertEqual(owner.results.count, 1)
        XCTAssertEqual(try XCTUnwrap(owner.results.first).get(), newURL)
        XCTAssertEqual(owner.resets, 1)
        XCTAssertFalse(owner.presented)
    }

    func testResetRemovalPreservesCompletionButRetirementSuppressesIt() async throws {
        let previous = FileDialogManager.provider
        FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
        defer { FileDialogManager.provider = previous }
        let picked = URL(fileURLWithPath: "C:/dialog-fixture/reset.txt")
        for kind in NativeDialogOwnershipPresenter.Kind.allCases {
            for retiresHost in [false, true] {
                let response: NativeDialogResponse = kind == .importer ? .selectedFiles([picked]) : .cancelled
                let driver = NativeDialogOwnershipDriver(response: response)
                let owner = NativeDialogOwnershipPresenter(driver: driver, kind: kind)
                defer { owner.cleanUp() }
                owner.onReset = {
                    owner.removePresenter()
                    if retiresHost {
                        owner.host.invalidateFileDialogRequests()
                        driver.session.invalidate()
                    }
                }
                owner.present()
                try driver.performNext()
                await owner.payloadReleased.wait()

                XCTAssertEqual(owner.resets, 1)
                XCTAssertFalse(owner.presented)
                XCTAssertEqual(owner.encodes, 0, "Cancelling export cannot run the encoder.")
                XCTAssertFalse(driver.session.hasPendingRequests)
                if kind == .importer && !retiresHost {
                    XCTAssertEqual(owner.results.count, 1)
                    XCTAssertEqual(try XCTUnwrap(owner.results.first).get(), picked)
                    XCTAssertEqual(owner.events, ["reset", "completion"])
                } else {
                    XCTAssertTrue(owner.results.isEmpty)
                    XCTAssertEqual(owner.events, ["reset"])
                }
            }
        }
    }

    func testExplicitNativeCapabilityPreservesInjectedWin32AndLegacyInlineProviders() async throws {
        let previous = FileDialogManager.provider
        defer { FileDialogManager.provider = previous }
        let driver = NativeDialogOwnershipDriver(response: .cancelled)
        var events: [String] = []
        let injected = Win32FileDialogProvider(
            openDialog: { _ in
                events.append("open")
                return false
            },
            saveDialog: { _ in
                events.append("save")
                return false
            },
            extendedError: {
                events.append("error")
                return 0x3002
            },
            activeWindow: {
                events.append("owner")
                return nil
            })
        XCTAssertFalse(injected.supportsNativeOwnerRequests)
        FileDialogManager.provider = injected
        FileDialogManager.requestOpenFileDialog(nativeSession: driver.session) {
            self.assertOutcome($0, equals: .fileFailure(.nativeFailure(0x3002)))
            events.append("open-completion")
        }
        events.append("after-open")
        FileDialogManager.requestSaveFileDialog(nativeSession: driver.session) {
            guard case .failed(let error) = $0 else {
                return XCTFail("The injected save failure must remain a failure.")
            }
            XCTAssertEqual(error as? FileDialogError, .nativeFailure(0x3002))
            events.append("save-completion")
        }
        events.append("after-save")
        XCTAssertEqual(
            events,
            [
                "owner", "open", "error", "open-completion", "after-open",
                "owner", "save", "error", "save-completion", "after-save",
            ])
        XCTAssertEqual(driver.sink.submissionCount, 0)
        XCTAssertFalse(driver.session.hasPendingRequests)

        let inlineOwner = NativeDialogOwnershipPresenter(driver: driver)
        defer { inlineOwner.cleanUp() }
        inlineOwner.present()
        XCTAssertFalse(inlineOwner.presented)
        XCTAssertEqual(inlineOwner.resets, 1)
        XCTAssertEqual(inlineOwner.results.count, 1, "The injected host path must still finish before returning.")
        guard case .failure(let inlineError) = try XCTUnwrap(inlineOwner.results.first) else {
            return XCTFail("A native failure must not become a successful retained operation.")
        }
        XCTAssertEqual(inlineError as? FileDialogError, .nativeFailure(0x3002))
        XCTAssertEqual(inlineOwner.events, ["reset", "completion"])
        XCTAssertEqual(driver.sink.submissionCount, 0)

        let picked = URL(fileURLWithPath: "C:/dialog-fixture/legacy.txt")
        let legacy = NativeDialogOwnershipLegacyProvider(picked: picked)
        FileDialogManager.provider = legacy
        var imported: [URL]?
        var saved: URL?
        FileDialogManager.requestOpenFileDialog(owner: .hosted(nil), nativeSession: driver.session) {
            guard case .selected(let urls) = $0 else {
                return XCTFail("The legacy open provider must complete inline.")
            }
            imported = urls
        }
        FileDialogManager.requestSaveFileDialog(owner: .hosted(nil), nativeSession: driver.session) {
            guard case .selected(let url) = $0 else { return XCTFail("The legacy save provider must complete inline.") }
            saved = url
        }
        XCTAssertEqual(imported, [picked])
        XCTAssertEqual(saved, picked)
        XCTAssertEqual(legacy.calls, ["open", "save"])
        XCTAssertEqual(driver.sink.submissionCount, 0)
    }

    func testInheritedContextAppliesDeferredColorInScopeAndRejectsRetiredChoice() async throws {
        let previous = ColorDialogManager.provider
        ColorDialogManager.provider = NativeDialogOwnershipCapableColorProvider()
        defer { ColorDialogManager.provider = previous }
        let initial = Color(red: 0.9, green: 0.1, blue: 0.2, alpha: 0.4)
        let chosen = Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.4)
        for retiresSession in [false, true] {
            let driver = NativeDialogOwnershipDriver(response: .selectedColor(chosen))
            let state = NativeDialogOwnershipColorState(selection: initial)
            try startColorChoice(driver: driver, state: state)
            XCTAssertNil(ViewBuildContextScope.current)
            XCTAssertTrue(driver.session.hasPendingRequests)
            XCTAssertNotNil(state.payload, "Only the admitted selection still needs the captured context.")
            XCTAssertEqual(state.selection, initial)
            XCTAssertEqual(state.writes, 0)
            if retiresSession { driver.session.invalidate() }

            try driver.performNext()
            await state.payloadReleased.wait()

            XCTAssertFalse(driver.session.hasPendingRequests)
            XCTAssertNil(state.payload)
            XCTAssertNil(ViewBuildContextScope.current)
            if retiresSession {
                XCTAssertEqual(state.selection, initial)
                XCTAssertEqual(state.writes, 0)
                XCTAssertEqual(state.invalidations, 0)
            } else {
                XCTAssertEqual(state.selection, chosen)
                XCTAssertEqual(state.writes, 1)
                XCTAssertEqual(state.invalidations, 1)
                XCTAssertTrue(state.sawCapturedSession)
                XCTAssertEqual(state.capturedScheme, .light)
                XCTAssertEqual(state.capturedSize, Size(width: 128, height: 80))
            }
            guard case .color(let capturedInitial) = try XCTUnwrap(driver.probe.requests.first) else {
                return XCTFail("ColorPicker must submit the native color command.")
            }
            XCTAssertEqual(capturedInitial, initial)
        }
    }

    func testColorPickerQueuesOwnerAcquisitionAndRejectsReplacementBeforeDispatch() async throws {
        let previous = ColorDialogManager.provider
        defer { ColorDialogManager.provider = previous }
        let initial = Color(red: 0.8, green: 0.1, blue: 0.2, alpha: 1)
        let chosen = Color(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
        for replacesOwner in [false, true] {
            let provider = NativeDialogOwnershipCapableColorProvider()
            ColorDialogManager.provider = provider
            let driver = NativeDialogOwnershipDriver(response: .selectedColor(chosen))
            let occurrence = try NativeDialogOwnershipOccurrence()
            defer { occurrence.close() }
            let ownerRequests = NativeDialogOwnershipOwnerRequests()
            let state = NativeDialogOwnershipColorState(selection: initial)
            try startQueuedColorChoice(owner: occurrence.owner, ownerRequests: ownerRequests, state: state)
            let readsBeforeDelivery = state.reads
            XCTAssertEqual(ownerRequests.requestCount, 1)
            XCTAssertEqual(ownerRequests.pendingCount, 1)
            XCTAssertEqual(provider.calls, 0)
            XCTAssertEqual(driver.sink.submissionCount, 0)
            XCTAssertFalse(driver.session.hasPendingRequests)
            XCTAssertEqual(state.selection, initial)
            XCTAssertNotNil(state.payload)
            if replacesOwner {
                let replacement = try occurrence.replaceOwner()
                XCTAssertFalse(occurrence.owner.isLive)
                XCTAssertTrue(replacement.isLive)
                XCTAssertEqual(replacement.identity, occurrence.owner.identity)
                XCTAssertFalse(replacement === occurrence.owner)
            } else {
                try occurrence.rebuildSameOwner()
                XCTAssertTrue(occurrence.owner.isLive)
            }

            try ownerRequests.deliverNext(driver.session)

            XCTAssertEqual(ownerRequests.pendingCount, 0)
            if replacesOwner {
                await state.payloadReleased.wait()
                XCTAssertEqual(driver.sink.submissionCount, 0)
                XCTAssertEqual(state.reads, readsBeforeDelivery)
                XCTAssertEqual(state.selection, initial)
                XCTAssertEqual(state.writes, 0)
                XCTAssertEqual(state.invalidations, 0)
            } else {
                XCTAssertEqual(driver.sink.submissionCount, 1)
                XCTAssertTrue(driver.session.hasPendingRequests)
                XCTAssertEqual(state.selection, initial)
                try driver.performNext()
                await state.payloadReleased.wait()
                XCTAssertEqual(state.selection, chosen)
                XCTAssertEqual(state.writes, 1)
                XCTAssertEqual(state.invalidations, 1)
                XCTAssertEqual(state.capturedWindowKey, driver.session.windowKey)
                XCTAssertEqual(state.capturedOwner, ObjectIdentifier(occurrence.owner))
                XCTAssertEqual(state.capturedScheme, .light)
                XCTAssertEqual(state.capturedSize, Size(width: 111, height: 77))
            }
            XCTAssertEqual(provider.calls, 0)
            XCTAssertFalse(driver.session.hasPendingRequests)
            XCTAssertNil(ViewBuildContextScope.current)
        }
    }

    func testQueuedOwnerAcquisitionKeepsInlineProviderResultsDeferredAndOwned() async throws {
        let previous = ColorDialogManager.provider
        defer { ColorDialogManager.provider = previous }
        let initial = Color(red: 0.7, green: 0.3, blue: 0.1, alpha: 1)
        let chosen = Color(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
        for retiresDuringProvider in [false, true] {
            let provider = NativeDialogOwnershipInlineColorProvider(chosen: chosen)
            ColorDialogManager.provider = provider
            let driver = NativeDialogOwnershipDriver(response: .cancelled)
            let occurrence = try NativeDialogOwnershipOccurrence()
            let ownerRequests = NativeDialogOwnershipOwnerRequests()
            let state = NativeDialogOwnershipColorState(selection: initial)
            var providerSawResolvedScope = false
            provider.onChoose = {
                let context = ViewBuildContextScope.current
                providerSawResolvedScope =
                    context?.nativeDialogSession === driver.session
                    && context?.viewIdentity.installedOwner === occurrence.owner
                if retiresDuringProvider { occurrence.close() }
            }
            defer {
                provider.onChoose = nil
                occurrence.close()
            }
            try startQueuedColorChoice(owner: occurrence.owner, ownerRequests: ownerRequests, state: state)
            XCTAssertEqual(ownerRequests.pendingCount, 1)
            XCTAssertTrue(provider.requests.isEmpty)
            XCTAssertEqual(driver.sink.submissionCount, 0)
            XCTAssertEqual(state.writes, 0)

            try ownerRequests.deliverNext(driver.session)
            await state.payloadReleased.wait()

            XCTAssertTrue(providerSawResolvedScope)
            XCTAssertEqual(provider.requests, [initial])
            XCTAssertEqual(driver.sink.submissionCount, 0, "A legacy provider still returns inline after acquisition.")
            XCTAssertFalse(driver.session.hasPendingRequests)
            if retiresDuringProvider {
                XCTAssertFalse(occurrence.owner.isLive)
                XCTAssertEqual(state.selection, initial)
                XCTAssertEqual(
                    state.writes, 0, "The queued acquisition made this result deferred before the provider ran.")
                XCTAssertEqual(state.invalidations, 0)
            } else {
                XCTAssertEqual(state.selection, chosen)
                XCTAssertEqual(state.writes, 1)
                XCTAssertEqual(state.invalidations, 1)
                XCTAssertEqual(state.capturedWindowKey, driver.session.windowKey)
                XCTAssertEqual(state.capturedOwner, ObjectIdentifier(occurrence.owner))
            }
            XCTAssertNil(ViewBuildContextScope.current)
        }
    }

    func testActualImporterRestoresOriginalEnvironmentForDeferredGetterResetAndCompletion() async throws {
        let previous = FileDialogManager.provider
        defer { FileDialogManager.provider = previous }
        let picked = URL(fileURLWithPath: "C:/dialog-fixture/scoped-import.txt")
        for switchesProviderInGetter in [false, true] {
            let legacy = NativeDialogOwnershipLegacyProvider(picked: picked)
            if switchesProviderInGetter {
                FileDialogManager.provider = legacy
            } else {
                FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
            }
            let driver = NativeDialogOwnershipDriver(response: .selectedFiles([picked]))
            let state = NativeDialogOwnershipImportState()
            if switchesProviderInGetter {
                state.onFirstPresentationRead = {
                    XCTAssertNil(
                        ViewBuildContextScope.current,
                        "The first getter still belongs to the initially injected, inline provider path.")
                    // Construction stores native-call closures only. The actual
                    // request must still execute through this test's fake session.
                    FileDialogManager.provider = Win32FileDialogProvider()
                }
            }
            let (host, scope) = try startScopedImporter(driver: driver, state: state)
            defer {
                host.invalidateFileDialogRequests()
                host.setContent(Component { _ in ViewNode() })
            }
            let entriesBeforeReply = scope.entries
            XCTAssertTrue(state.observations.isEmpty)
            XCTAssertTrue(state.results.isEmpty)
            XCTAssertTrue(legacy.calls.isEmpty, "The getter selected native dispatch before any provider invocation.")
            XCTAssertEqual(driver.sink.submissionCount, 1)
            XCTAssertNil(ViewBuildContextScope.current)
            let unrelated = ViewBuildContext(
                canvasSizeProvider: { Size(width: 999, height: 777) }, invalidateHandler: {},
                environmentValuesProvider: { EnvironmentValues(colorScheme: .dark) })

            let execution: Result<Void, Error> = ViewBuildContextScope.withCurrent(unrelated) {
                Result {
                    try driver.performNext()
                    XCTAssertTrue(state.results.isEmpty, "Native execution cannot invoke retained callbacks inline.")
                    XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, Size(width: 999, height: 777))
                }
            }
            try execution.get()
            await state.delivered.wait()

            XCTAssertNil(ViewBuildContextScope.current)
            XCTAssertGreaterThan(scope.entries, entriesBeforeReply)
            XCTAssertFalse(driver.session.hasPendingRequests)
            XCTAssertFalse(state.presented)
            XCTAssertEqual(state.resets, 1)
            XCTAssertEqual(state.results.count, 1)
            XCTAssertEqual(try XCTUnwrap(state.results.first).get(), picked)
            XCTAssertEqual(state.observations.map(\.phase), ["get", "reset", "completion"])
            for observation in state.observations {
                XCTAssertEqual(observation.size, Size(width: 321, height: 123), observation.phase)
                XCTAssertEqual(observation.scheme, .light, observation.phase)
                XCTAssertEqual(observation.model, ObjectIdentifier(state.model), observation.phase)
                XCTAssertEqual(observation.windowKey, driver.session.windowKey, observation.phase)
            }
            XCTAssertEqual(state.observedObjects, Array(repeating: ObjectIdentifier(state.model), count: 3))
        }
    }

    func testClosedActualImporterRefusesScopeAndApplicationReadsBeforeLateReply() async throws {
        let previous = FileDialogManager.provider
        FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
        defer { FileDialogManager.provider = previous }
        for alsoRetiresSession in [false, true] {
            let driver = NativeDialogOwnershipDriver(
                response: .selectedFiles([URL(fileURLWithPath: "C:/dialog-fixture/closed-import.txt")]))
            let state = NativeDialogOwnershipImportState()
            let (host, scope) = try startScopedImporter(driver: driver, state: state)
            defer {
                host.invalidateFileDialogRequests()
                driver.session.invalidate()
                host.setContent(Component { _ in ViewNode() })
            }
            host.invalidateFileDialogRequests()
            if alsoRetiresSession { driver.session.invalidate() }
            host.setContent(Component { _ in ViewNode() })
            let entriesBeforeReply = scope.entries
            let readsBeforeReply = state.environmentReads
            XCTAssertTrue(driver.session.hasPendingRequests)
            XCTAssertNotNil(state.payload)

            try driver.performNext()
            await state.payloadReleased.wait()

            XCTAssertNil(state.payload)
            XCTAssertFalse(driver.session.hasPendingRequests)
            XCTAssertEqual(scope.entries, entriesBeforeReply, "Revocation must be checked before entering the scope.")
            XCTAssertEqual(state.environmentReads, readsBeforeReply)
            XCTAssertTrue(state.observations.isEmpty)
            XCTAssertTrue(state.observedObjects.isEmpty)
            XCTAssertTrue(state.results.isEmpty)
            XCTAssertTrue(state.presented)
            XCTAssertEqual(state.resets, 0)
            XCTAssertNil(ViewBuildContextScope.current)
        }
    }

    func testAdmittedAlertImportButtonCompletesAfterItsConstructionOwnerRetires() async throws {
        let previous = FileDialogManager.provider
        FileDialogManager.provider = NativeDialogOwnershipCapableProvider()
        defer { FileDialogManager.provider = previous }
        let picked = URL(fileURLWithPath: "C:/dialog-fixture/alert-import.txt")
        for acquiresOwnerLater in [false, true] {
            let driver = NativeDialogOwnershipDriver(response: .selectedFiles([picked]))
            let state = NativeDialogOwnershipImportState()
            let ownerRequests = acquiresOwnerLater ? NativeDialogOwnershipOwnerRequests() : nil
            let (constructionOwner, runtime) = try startAdmittedAlertImport(
                driver: driver, state: state, ownerRequests: ownerRequests)
            defer {
                driver.session.invalidate()
                runtime.stopRenderLifecycleCallbacks()
                runtime.cancelRenderLifecycleTasks()
            }
            XCTAssertFalse(constructionOwner.isLive)
            XCTAssertFalse(state.presented)
            XCTAssertEqual(state.resets, 1)
            XCTAssertEqual(state.invalidations, 1)
            XCTAssertTrue(runtime.root.children.isEmpty)
            XCTAssertTrue(driver.session.isValid)
            XCTAssertNotNil(state.payload)
            XCTAssertTrue(state.importedURLs.isEmpty)
            if let ownerRequests {
                XCTAssertEqual(ownerRequests.pendingCount, 1)
                XCTAssertEqual(driver.sink.submissionCount, 0)
                XCTAssertFalse(driver.session.hasPendingRequests)
                try ownerRequests.deliverNext(driver.session)
            }
            XCTAssertEqual(driver.sink.submissionCount, 1)
            XCTAssertTrue(driver.session.hasPendingRequests)

            try driver.performNext()
            await state.payloadReleased.wait()

            XCTAssertFalse(driver.session.hasPendingRequests)
            XCTAssertEqual(state.importedURLs, [picked])
            XCTAssertEqual(
                state.callbackHadInstalledOwner, false, "The admitted invocation must not reuse its retired mount.")
            XCTAssertEqual(state.invalidations, 2)
            XCTAssertEqual(state.observations.map(\.phase), ["import"])
            let observation = try XCTUnwrap(state.observations.first)
            XCTAssertEqual(observation.scheme, .light)
            XCTAssertEqual(observation.model, ObjectIdentifier(state.model))
            XCTAssertEqual(observation.windowKey, driver.session.windowKey)
            XCTAssertNil(ViewBuildContextScope.current)
        }
    }

    private func startAdmittedAlertImport(
        driver: NativeDialogOwnershipDriver, state: NativeDialogOwnershipImportState,
        ownerRequests: NativeDialogOwnershipOwnerRequests? = nil
    ) throws -> (StateMountOwner, RetainedViewRuntime) {
        let registry = StateMountRegistry()
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        let identity = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ImportButton.self))])
        let owner = try XCTUnwrap(epoch.owner(at: identity))
        guard epoch.prepareForAdoption() else { throw NativeDialogOwnershipTestFailure.cannotAdoptOwner }
        epoch.commitAdoption()
        XCTAssertTrue(owner.isLive)
        let payload = NativeDialogOwnershipPayload(released: state.payloadReleased)
        state.payload = payload
        state.presented = true
        state.recordsScope = true
        var viewIdentity = ViewIdentityContext()
        viewIdentity.path = identity
        viewIdentity.installedOwner = owner
        let context = ViewBuildContext(
            viewIdentity: viewIdentity, nativeDialogSession: ownerRequests == nil ? driver.session : nil,
            nativeDialogOwnerRequest: { completion in
                if let ownerRequests {
                    ownerRequests.request(completion)
                } else {
                    completion(driver.session)
                }
            },
            canvasSizeProvider: { Size(width: 320, height: 200) },
            invalidateHandler: { withExtendedLifetime(payload) { state.invalidations += 1 } },
            environmentValuesProvider: {
                var values = EnvironmentValues(colorScheme: .light)
                values.environmentObjects.setObject(state.model)
                return values
            })
        let declaration = RetainedAlertDeclaration.raw(
            configuration: RetainedAlertConfiguration(
                validate: { admitted in admitted() && state.presented },
                reset: {
                    state.presented = false
                    state.resets += 1
                    registry.close()
                },
                invalidate: { state.invalidations += 1 }))
        let actionScope = RetainedAlertActionScope(declaration: declaration, context: context)
        let actionContext = context.withEnvironmentValue(\.retainedAlertActionScope, actionScope)
        XCTAssertTrue(actionContext.viewIdentity.installedOwner === owner)
        let runtime = RetainedViewRuntime(root: ViewNode())
        runtime.setRootSize(IntSize(width: 320, height: 200))
        let container = ViewNode()
        container.frame = Rect(x: 0, y: 0, width: 320, height: 200)
        container.layoutMode = .absolute
        let background = ViewNode()
        background.frame = container.frame
        let overlay = ViewNode()
        overlay.frame = container.frame
        overlay.layoutMode = .absolute
        overlay.accessibilityTraits.insert(.isModal)
        overlay.isHitTestVisible = true
        let importButton = ImportButton(
            supportedContentTypes: [.plainText], label: { Color.clear },
            onImport: { items in
                state.importedURLs = items.compactMap { $0 as? URL }
                state.callbackHadInstalledOwner = ViewBuildContextScope.current?.viewIdentity.installedOwner != nil
                state.captureScope(phase: "import")
            })
        let button = importButton.makeComponent(context: actionContext).makeNode(runtime: runtime)
        button.frame = Rect(x: 40, y: 40, width: 120, height: 40)
        overlay.addChild(button)
        container.addChild(background)
        container.addChild(overlay)
        runtime.root.addChild(container)
        declaration.materialize(on: container, runtime: runtime)
        _ = try XCTUnwrap(runtime.resolvedLayoutFrame(of: runtime.root))
        XCTAssertTrue(runtime.presentationModalSnapshot === overlay)
        XCTAssertTrue(runtime.permitsPresentationAction(on: button, within: overlay))

        try XCTUnwrap(button.onActivate)()

        XCTAssertEqual(
            driver.sink.submissionCount, ownerRequests == nil ? 1 : 0,
            "The retained alert receipt must admit the actual ImportButton without bypassing owner acquisition.")
        XCTAssertFalse(owner.isLive, "Alert reset retires the construction owner before the native result.")
        container.removeFromParent()
        _ = try XCTUnwrap(runtime.resolvedLayoutFrame(of: runtime.root))
        return (owner, runtime)
    }

    private func startScopedImporter(
        driver: NativeDialogOwnershipDriver, state: NativeDialogOwnershipImportState
    ) throws -> (ComponentHost, NativeDialogOwnershipScopeSpy) {
        let context = ViewBuildContext(
            nativeDialogSession: driver.session,
            canvasSizeProvider: { Size(width: 321, height: 123) }, invalidateHandler: {},
            observedObjectHandler: { state.observedObjects.append(ObjectIdentifier($0)) },
            environmentValuesProvider: {
                state.environmentReads += 1
                return EnvironmentValues(colorScheme: .dark)
            })
        let readsBeforeCapture = state.environmentReads
        _ = FileDialogInvocationContext(context)
        XCTAssertEqual(state.environmentReads, readsBeforeCapture, "Capturing a provider must not evaluate it.")
        let payload = NativeDialogOwnershipPayload(released: state.payloadReleased)
        state.payload = payload
        let binding = Binding(
            get: {
                let onRead = state.onFirstPresentationRead
                state.onFirstPresentationRead = nil
                onRead?()
                state.captureScope(phase: "get")
                return state.presented
            },
            set: { value in
                state.presented = value
                if !value {
                    state.resets += 1
                    state.captureScope(phase: "reset")
                }
            })
        let view = Color.clear
            .fileImporter(isPresented: binding, allowedContentTypes: [.plainText]) { [payload] result in
                withExtendedLifetime(payload) {
                    state.results.append(result)
                    state.captureScope(phase: "completion")
                    state.delivered.signal()
                }
            }
            .environmentObject(state.model)
            .environment(\.colorScheme, .light)
        let host = ComponentHost(runtime: RetainedViewRuntime(root: ViewNode()))
        host.nativeDialogSession = driver.session
        host.setContent(view.makeComponent(context: context))
        let presenter = try XCTUnwrap(firstImporter(in: host.runtime.root))
        var configuration = try XCTUnwrap(presenter.fileImporterConfiguration)
        let scope = NativeDialogOwnershipScopeSpy(base: try XCTUnwrap(configuration.invocationScope))
        configuration.invocationScope = scope
        presenter.fileImporterConfiguration = configuration
        state.presented = true
        host.processPendingFileDialogs()
        state.recordsScope = true
        return (host, scope)
    }

    private func firstImporter(in node: ViewNode) -> ViewNode? {
        if node.fileImporterConfiguration != nil { return node }
        for child in node.children {
            if let presenter = firstImporter(in: child) { return presenter }
        }
        return nil
    }

    private func startColorChoice(
        driver: NativeDialogOwnershipDriver, state: NativeDialogOwnershipColorState
    ) throws {
        let payload = NativeDialogOwnershipPayload(released: state.payloadReleased)
        state.payload = payload
        var ownerRequestCount = 0
        let context = ViewBuildContext(
            nativeDialogSession: driver.session,
            nativeDialogOwnerRequest: { completion in
                ownerRequestCount += 1
                completion(driver.session)
            },
            canvasSizeProvider: { Size(width: 200, height: 120) },
            invalidateHandler: {
                withExtendedLifetime(payload) { state.invalidations += 1 }
            })
        let copies = [
            context.withCanvasSize(Size(width: 128, height: 80)),
            context.withEnabled(true),
            context.withForegroundColor(.black),
            context.withTint(.black),
            context.withFont(.body),
            context.withFontDesign(.monospaced),
            context.withFontWeight(.semibold),
            context.withTextAlignment(.leading),
            context.withLineLimit(1),
            context.withTruncationMode(.tail),
            context.withAllowsTightening(false),
            context.withTextCase(.uppercase),
            context.withLabelsHidden(true),
            context.withControlSize(.small),
            context.withStackAxis(.vertical),
            context.withButtonStyle(.automatic),
            context.withPickerStyle(.automatic),
            context.withEnvironmentValue(\.colorScheme, .light),
            context.withEnvironmentValues(EnvironmentValues(colorScheme: .light)),
            context.withTransformedEnvironmentValue(\.isEnabled) { $0 = false },
            context.withNavigationDestinationHandler { _, _ in },
            context.withNavigationValueHandler { _ in false },
            context.retainedAlertInvocationContext(),
            context.retainedFileDialogInvocationContext(),
            context.withViewIdentityPrefix([.slot(1)]),
        ]
        for copy in copies {
            XCTAssertTrue(copy.nativeDialogSession === driver.session)
            XCTAssertNotNil(copy.nativeDialogOwnerRequest)
            let before = ownerRequestCount
            copy.withNativeDialogOwner { XCTAssertTrue($0 === driver.session) }
            XCTAssertEqual(ownerRequestCount, before + 1, "The inherited hook must precede the stored session.")
        }
        let inherited =
            context
            .withCanvasSize(Size(width: 128, height: 80))
            .withEnabled(true)
            .withEnvironmentValue(\.colorScheme, .light)
            .withEnvironmentValue(\.colorPickerUsesNativeDialog, true)
            .withLineLimit(1)
            .withControlSize(.small)
        let binding = Binding(
            get: { state.selection },
            set: { color in
                state.selection = color
                state.writes += 1
                state.sawCapturedSession = ViewBuildContextScope.current?.nativeDialogSession === driver.session
                state.capturedScheme = Environment<ColorScheme>(\.colorScheme).wrappedValue
                state.capturedSize = ViewBuildContextScope.current?.canvasSize
            })
        let view = ColorPicker("Pick", selection: binding)
        let host = ComponentHost(runtime: RetainedViewRuntime(root: ViewNode()))
        host.setContent(view.makeComponent(context: inherited))
        let activate = try XCTUnwrap(firstActivation(in: host.runtime.root))
        activate()
        // The unmounted fixture's tree and construction context leave scope.
        // Its admitted completion alone retains the captured environment.
        host.setContent(Component { _ in ViewNode() })
        host.invalidateFileDialogRequests()
    }

    private func startQueuedColorChoice(
        owner: StateMountOwner, ownerRequests: NativeDialogOwnershipOwnerRequests,
        state: NativeDialogOwnershipColorState
    ) throws {
        let payload = NativeDialogOwnershipPayload(released: state.payloadReleased)
        state.payload = payload
        var identity = ViewIdentityContext()
        identity.path = owner.identity
        identity.installedOwner = owner
        let context = ViewBuildContext(
            viewIdentity: identity,
            nativeDialogOwnerRequest: { ownerRequests.request($0) },
            canvasSizeProvider: { Size(width: 111, height: 77) },
            invalidateHandler: { withExtendedLifetime(payload) { state.invalidations += 1 } }
        )
        .withEnvironmentValue(\.colorScheme, .light)
        .withEnvironmentValue(\.colorPickerUsesNativeDialog, true)
        XCTAssertNil(context.nativeDialogSession)
        let binding = Binding(
            get: {
                state.reads += 1
                return state.selection
            },
            set: { color in
                state.selection = color
                state.writes += 1
                let current = ViewBuildContextScope.current
                state.capturedWindowKey = current?.nativeDialogSession?.windowKey
                state.capturedOwner = current?.viewIdentity.installedOwner.map { ObjectIdentifier($0) }
                state.capturedScheme = Environment<ColorScheme>(\.colorScheme).wrappedValue
                state.capturedSize = current?.canvasSize
            })
        let host = ComponentHost(runtime: RetainedViewRuntime(root: ViewNode()))
        let view = ColorPicker(selection: binding) { Color.clear }
        host.setContent(view.makeComponent(context: context))
        let activate = try XCTUnwrap(firstActivation(in: host.runtime.root))
        let readsBeforeActivation = state.reads
        activate()
        XCTAssertEqual(state.reads, readsBeforeActivation, "Selection must wait until the owner is supplied.")
        host.setContent(Component { _ in ViewNode() })
        host.invalidateFileDialogRequests()
    }

    private func firstActivation(in node: ViewNode) -> (() -> Void)? {
        if let activate = node.onActivate { return activate }
        for child in node.children {
            if let activate = firstActivation(in: child) { return activate }
        }
        return nil
    }

    private func assertOutcome(
        _ outcome: DialogRequestOutcome<[URL]>, equals expected: NativeDialogOwnershipExpectedOutcome,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch (outcome, expected) {
        case (.cancelled, .cancelled):
            break
        case (.failed(let error), .fileFailure(let expected)):
            XCTAssertEqual(error as? FileDialogError, expected, file: file, line: line)
        case (.failed(let error), .nativeFailure(let expected)):
            XCTAssertEqual(error as? NativeDialogFailure, expected, file: file, line: line)
        default:
            XCTFail(
                "The dialog result changed its success, cancellation, failure, or revocation category.", file: file,
                line: line)
        }
    }
}

private enum NativeDialogOwnershipExpectedOutcome {
    case cancelled
    case fileFailure(FileDialogError)
    case nativeFailure(NativeDialogFailure)
}

private enum NativeDialogOwnershipTestFailure: Error {
    case missingCommand
    case missingOwnerRequest
    case unexpectedSerialization
    case cannotAdoptOwner
}

@MainActor
private final class NativeDialogOwnershipEnvironmentModel: ObservableObject {}

private struct NativeDialogOwnershipScopeObservation {
    let phase: String
    let size: Size?
    let scheme: ColorScheme?
    let model: ObjectIdentifier?
    let windowKey: NativeWindowKey?
}

@MainActor
private final class NativeDialogOwnershipImportState {
    let model = NativeDialogOwnershipEnvironmentModel()
    let delivered = NativeDialogOwnershipSignal()
    let payloadReleased = NativeDialogOwnershipSignal()
    weak var payload: NativeDialogOwnershipPayload?
    var presented = false
    var resets = 0
    var recordsScope = false
    var onFirstPresentationRead: (() -> Void)?
    var environmentReads = 0
    var invalidations = 0
    var importedURLs: [URL] = []
    var callbackHadInstalledOwner: Bool?
    var observations: [NativeDialogOwnershipScopeObservation] = []
    var observedObjects: [ObjectIdentifier] = []
    var results: [Result<URL, Error>] = []

    func captureScope(phase: String) {
        guard recordsScope else { return }
        let context = ViewBuildContextScope.current
        let availableModel = context?.environmentValues.environmentObjects.object(
            NativeDialogOwnershipEnvironmentModel.self)
        // A missing scope must produce an assertion, not the wrapper's fatal
        // missing-object diagnostic. When present, exercise the real wrapper.
        let resolvedModel = availableModel.map { _ in
            EnvironmentObject<NativeDialogOwnershipEnvironmentModel>().wrappedValue
        }
        observations.append(
            NativeDialogOwnershipScopeObservation(
                phase: phase, size: context?.canvasSize,
                scheme: context.map { _ in Environment<ColorScheme>(\.colorScheme).wrappedValue },
                model: resolvedModel.map { ObjectIdentifier($0) },
                windowKey: context?.nativeDialogSession?.windowKey))
    }
}

@MainActor
private final class NativeDialogOwnershipScopeSpy: RetainedFileDialogInvocationScope {
    private let base: any RetainedFileDialogInvocationScope
    private(set) var entries = 0

    init(base: any RetainedFileDialogInvocationScope) { self.base = base }

    func withInvocation(_ body: @MainActor () -> Void) {
        entries += 1
        base.withInvocation(body)
    }
}

@MainActor
private final class NativeDialogOwnershipColorState {
    var selection: Color
    var reads = 0
    var writes = 0
    var invalidations = 0
    var sawCapturedSession = false
    var capturedScheme: ColorScheme?
    var capturedSize: Size?
    var capturedWindowKey: NativeWindowKey?
    var capturedOwner: ObjectIdentifier?
    let payloadReleased = NativeDialogOwnershipSignal()
    weak var payload: NativeDialogOwnershipPayload?

    init(selection: Color) { self.selection = selection }
}

@MainActor
private final class NativeDialogOwnershipOwnerRequests {
    typealias Completion = @MainActor (NativeDialogSession) -> Void
    private var pending: [Completion] = []
    private(set) var requestCount = 0

    var pendingCount: Int { pending.count }

    func request(_ completion: @escaping Completion) {
        requestCount += 1
        pending.append(completion)
    }

    func deliverNext(_ session: NativeDialogSession) throws {
        guard !pending.isEmpty else { throw NativeDialogOwnershipTestFailure.missingOwnerRequest }
        let completion = pending.removeFirst()
        completion(session)
    }
}

@MainActor
private final class NativeDialogOwnershipOccurrence {
    private let registry: StateMountRegistry
    let owner: StateMountOwner

    init() throws {
        let registry = StateMountRegistry()
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        let identity = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ColorPicker.self))])
        let owner = try XCTUnwrap(epoch.owner(at: identity))
        guard epoch.prepareForAdoption() else { throw NativeDialogOwnershipTestFailure.cannotAdoptOwner }
        epoch.commitAdoption()
        self.registry = registry
        self.owner = owner
    }

    func rebuildSameOwner() throws {
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        XCTAssertTrue(try XCTUnwrap(epoch.owner(at: owner.identity)) === owner)
        guard epoch.prepareForAdoption() else { throw NativeDialogOwnershipTestFailure.cannotAdoptOwner }
        epoch.commitAdoption()
    }

    func replaceOwner() throws -> StateMountOwner {
        let removal = try XCTUnwrap(registry.beginRootBuild())
        guard removal.prepareForAdoption() else { throw NativeDialogOwnershipTestFailure.cannotAdoptOwner }
        removal.commitAdoption()
        registry.finishPendingRetirements()
        let insertion = try XCTUnwrap(registry.beginRootBuild())
        let replacement = try XCTUnwrap(insertion.owner(at: owner.identity))
        guard insertion.prepareForAdoption() else { throw NativeDialogOwnershipTestFailure.cannotAdoptOwner }
        insertion.commitAdoption()
        return replacement
    }

    func close() { registry.close() }
}

private final class NativeDialogOwnershipSignal: Sendable {
    private struct State: Sendable {
        var signalled = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    func signal() {
        let continuation = state.withLock { value in
            value.signalled = true
            let continuation = value.continuation
            value.continuation = nil
            return continuation
        }
        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let alreadySignalled = state.withLock { value in
                if value.signalled { return true }
                value.continuation = continuation
                return false
            }
            if alreadySignalled { continuation.resume() }
        }
    }
}

private final class NativeDialogOwnershipPayload: Sendable {
    private let released: NativeDialogOwnershipSignal

    init(released: NativeDialogOwnershipSignal) { self.released = released }
    deinit { released.signal() }
}

private final class NativeDialogOwnershipProbe: Sendable {
    private struct State: Sendable {
        var response: NativeDialogResponse
        var events: [String] = []
        var requests: [NativeDialogRequest] = []
        var handles: [NativeWindowHandle] = []
        var replies: [Result<NativeDialogResponse, NativeWindowOwnerFailure>] = []
    }

    private let state: Mutex<State>

    init(response: NativeDialogResponse) { state = Mutex(State(response: response)) }

    var response: NativeDialogResponse {
        get { state.withLock { $0.response } }
        set { state.withLock { $0.response = newValue } }
    }
    var events: [String] { state.withLock { $0.events } }
    var requests: [NativeDialogRequest] { state.withLock { $0.requests } }
    var handles: [NativeWindowHandle] { state.withLock { $0.handles } }
    var replies: [Result<NativeDialogResponse, NativeWindowOwnerFailure>] { state.withLock { $0.replies } }

    func record(_ event: String) { state.withLock { $0.events.append(event) } }

    func perform(_ request: NativeDialogRequest, handle: NativeWindowHandle) -> NativeDialogResponse {
        state.withLock { value in
            value.events.append("execute")
            value.requests.append(request)
            value.handles.append(handle)
            return value.response
        }
    }

    func receive(_ result: Result<NativeDialogResponse, NativeWindowOwnerFailure>) {
        state.withLock { value in
            value.events.append("reply")
            value.replies.append(result)
        }
    }
}

private final class NativeDialogOwnershipSink: NativeWindowCommandSink {
    private struct Waiter: Sendable {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State: Sendable {
        var commands: [any NativeWindowOwnerCommand] = []
        var submissionCount = 0
        var waiters: [Waiter] = []
    }

    private let state = Mutex(State())
    private let rejection: NativeWindowOwnerFailure?

    init(rejection: NativeWindowOwnerFailure? = nil) { self.rejection = rejection }

    var submissionCount: Int { state.withLock { $0.submissionCount } }
    var queuedCount: Int { state.withLock { $0.commands.count } }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        let ready = state.withLock { value in
            value.submissionCount += 1
            if rejection == nil { value.commands.append(command) }
            let submissionCount = value.submissionCount
            let ready = value.waiters.filter { $0.count <= submissionCount }
            value.waiters.removeAll { $0.count <= submissionCount }
            return ready
        }
        for waiter in ready { waiter.continuation.resume() }
        if let rejection {
            command.reject(rejection)
            return .rejected(rejection)
        }
        return .accepted
    }

    func takeNext() throws -> any NativeWindowOwnerCommand {
        let command: (any NativeWindowOwnerCommand)? = state.withLock { value in
            value.commands.isEmpty ? nil : value.commands.removeFirst()
        }
        guard let command else { throw NativeDialogOwnershipTestFailure.missingCommand }
        return command
    }

    func waitForSubmissionCount(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let isReady = state.withLock { value in
                if value.submissionCount >= count { return true }
                value.waiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if isReady { continuation.resume() }
        }
    }
}

private struct NativeDialogOwnershipSnapshot: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private final class NativeDialogOwnershipContext: NativeWindowOwnerContext {
    let surface: NativeWindowSurface
    let snapshotSource: any NativeWindowSnapshotSource
    let wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure> = { .success(()) }
    private let probe: NativeDialogOwnershipProbe
    private var attachments: [NativeWindowAttachmentID: any NativeWindowOwnerAttachment] = [:]
    private(set) var modalDepth = 0

    init(windowKey: NativeWindowKey, hasWindow: Bool = true, probe: NativeDialogOwnershipProbe) {
        let size = IntSize(width: 320, height: 200)
        let descriptor: SurfaceDescriptor
        if hasWindow, let handle = NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0xD1A106)) {
            descriptor = SurfaceDescriptor(windowHandle: handle, pixelSize: size, scaleFactor: 1)
        } else {
            descriptor = SurfaceDescriptor(offscreenPixelSize: size)
        }
        let surface = NativeWindowSurface(
            key: windowKey, generation: 1, descriptor: descriptor,
            geometry: NativeWindowGeometry(
                revision: 1, nativeSequence: 1, clientSize: size,
                clientScreenOrigin: Point(x: 10, y: 20), scaleFactor: 1, effectiveScaleFactor: 1,
                monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true))
        self.surface = surface
        snapshotSource = NativeDialogOwnershipSnapshot(surface: surface)
        self.probe = probe
    }

    func attachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? { attachments[id] }

    func install(_ attachment: any NativeWindowOwnerAttachment, for id: NativeWindowAttachmentID) throws {
        guard attachments[id] == nil else { throw NativeWindowOwnerFailure.duplicateAttachment(id) }
        attachments[id] = attachment
    }

    func removeAttachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? {
        attachments.removeValue(forKey: id)
    }

    func withNativeModal<Result>(_ body: () throws -> Result) rethrows -> Result {
        modalDepth += 1
        probe.record("modal-enter")
        defer {
            modalDepth -= 1
            probe.record("modal-exit")
        }
        return try body()
    }
}

@MainActor
private final class NativeDialogOwnershipDriver {
    let sink: NativeDialogOwnershipSink
    let probe: NativeDialogOwnershipProbe
    let context: NativeDialogOwnershipContext
    let session: NativeDialogSession

    init(response: NativeDialogResponse, rejection: NativeWindowOwnerFailure? = nil) {
        let key = NativeWindowKey()
        let sink = NativeDialogOwnershipSink(rejection: rejection)
        let probe = NativeDialogOwnershipProbe(response: response)
        self.sink = sink
        self.probe = probe
        context = NativeDialogOwnershipContext(windowKey: key, probe: probe)
        session = NativeDialogSession(
            windowKey: key, commandSink: sink,
            executor: NativeDialogExecutor { probe.perform($0, handle: $1) })
    }

    @discardableResult
    func performNext() throws -> any NativeWindowOwnerCommand {
        let command = try sink.takeNext()
        try command.execute(in: context)
        return command
    }
}

@MainActor
private final class NativeDialogOwnershipPresenter {
    enum Kind: CaseIterable, Equatable { case importer, exporter }

    let host: ComponentHost
    let node = ViewNode()
    let payloadReleased = NativeDialogOwnershipSignal()
    private(set) weak var payload: NativeDialogOwnershipPayload?
    var presented = false
    var resets = 0
    var encodes = 0
    var results: [Result<URL, Error>] = []
    var events: [String] = []
    var onReset: (() -> Void)?
    var onCompletion: (() -> Void)?

    private var binding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.presented ?? false },
            set: { [weak self] value in
                guard let self else { return }
                presented = value
                if !value {
                    resets += 1
                    events.append("reset")
                    onReset?()
                }
            })
    }

    init(driver: NativeDialogOwnershipDriver, kind: Kind = .importer) {
        host = ComponentHost(runtime: RetainedViewRuntime(root: ViewNode()))
        host.nativeDialogSession = driver.session
        let payload = NativeDialogOwnershipPayload(released: payloadReleased)
        self.payload = payload
        let completion: (Result<URL, Error>) -> Void = { [weak self, payload] result in
            withExtendedLifetime(payload) {
                guard let self else { return }
                self.results.append(result)
                self.events.append("completion")
                self.onCompletion?()
            }
        }
        switch kind {
        case .importer:
            node.fileImporterConfiguration = RetainedFileImporterConfiguration(
                isPresented: binding, allowedContentTypes: [.plainText], onCompletion: completion)
        case .exporter:
            node.fileExporterConfiguration = RetainedFileExporterConfiguration(
                isPresented: binding, document: payload,
                dataProvider: { [weak self] _ in
                    self?.encodes += 1
                    throw NativeDialogOwnershipTestFailure.unexpectedSerialization
                },
                contentType: .plainText, defaultFilename: "must-not-write.txt", onCompletion: completion)
        }
        host.runtime.root.addChild(node)
    }

    func present() {
        presented = true
        host.processPendingFileDialogs()
    }

    func removePresenter() {
        node.fileImporterConfiguration = nil
        node.fileExporterConfiguration = nil
        node.removeFromParent()
    }

    func cleanUp() {
        onReset = nil
        onCompletion = nil
        host.invalidateFileDialogRequests()
        host.nativeDialogSession?.invalidate()
        removePresenter()
    }
}

@MainActor
private final class NativeDialogOwnershipCapableProvider: NativeOwnerFileDialogProvider {
    let supportsNativeOwnerRequests = true

    func showOpenFileDialog(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool, defaultDirectory: URL?, title: String?
    ) -> [URL] {
        XCTFail("An explicitly native-capable request must use the injected command executor.")
        return []
    }

    func showSaveFileDialog(
        defaultFilename: String?, allowedExtensions: [String]?, defaultDirectory: URL?, title: String?
    ) -> URL? {
        XCTFail("An explicitly native-capable request must use the injected command executor.")
        return nil
    }
}

@MainActor
private final class NativeDialogOwnershipCapableColorProvider: NativeOwnerColorDialogProvider {
    let supportsNativeOwnerRequests = true
    private(set) var calls = 0

    func chooseColor(initial: Color) -> Color? {
        calls += 1
        XCTFail("The native color request must use the injected command executor.")
        return nil
    }
}

@MainActor
private final class NativeDialogOwnershipInlineColorProvider: ColorDialogProvider {
    private let chosen: Color
    private(set) var requests: [Color] = []
    var onChoose: (() -> Void)?

    init(chosen: Color) { self.chosen = chosen }

    func chooseColor(initial: Color) -> Color? {
        requests.append(initial)
        onChoose?()
        return chosen
    }
}

@MainActor
private final class NativeDialogOwnershipLegacyProvider: FileDialogProvider {
    private let picked: URL
    private(set) var calls: [String] = []

    init(picked: URL) { self.picked = picked }

    func showOpenFileDialog(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool, defaultDirectory: URL?, title: String?
    ) -> [URL] {
        calls.append("open")
        return [picked]
    }

    func showSaveFileDialog(
        defaultFilename: String?, allowedExtensions: [String]?, defaultDirectory: URL?, title: String?
    ) -> URL? {
        calls.append("save")
        return picked
    }
}
