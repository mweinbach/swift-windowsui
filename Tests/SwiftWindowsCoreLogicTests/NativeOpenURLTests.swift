import Foundation
import SwiftWindowsCore
import Synchronization
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These tests inject every shell executor and complete recorded commands with
/// copied reply values. They never launch a URL or create a native window.
@MainActor
final class NativeOpenURLTests: XCTestCase {
    func testShellResultThresholdKeepsExactNativeFailureCodes() async {
        for code in [UInt(0), 2, 5, 31, 32] {
            guard case .failed(.native(let operation, let actualCode)) = NativeDialogResponse.openURLResult(code) else {
                return XCTFail("A ShellExecute result at or below 32 must fail.")
            }
            XCTAssertEqual(operation, "ShellExecuteW")
            XCTAssertEqual(actualCode, UInt32(code))
        }
        for code in [UInt(33), 64, UInt.max] {
            guard case .openedURL = NativeDialogResponse.openURLResult(code) else {
                return XCTFail("A successful pointer-sized shell result must not become a signed failure.")
            }
        }
    }

    func testDefaultNativeActionCompletesOnlyAfterActualReply() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let fixture = NativeOpenURLTestFixture()
        defer { fixture.close() }
        let finished = expectation(description: "actual shell reply")
        var outcomes: [BuiltInOpenURLResult] = []
        var destination = try XCTUnwrap(URL(string: "https://example.invalid/original?q=1"))

        performBuiltInOpenURL(destination, action: .system, context: fixture.context) {
            outcomes.append($0)
            finished.fulfill()
        }
        destination = try XCTUnwrap(URL(string: "https://example.invalid/replacement"))

        XCTAssertTrue(outcomes.isEmpty, "Command admission is not .handled or .opened.")
        XCTAssertTrue(fixture.session.hasPendingRequests)
        XCTAssertEqual(fixture.sink.count, 1)
        XCTAssertTrue(shell.calls.isEmpty)
        let command = try XCTUnwrap(fixture.sink.command(at: 0))
        guard case .openURL(let operation, let target) = command.request else {
            return XCTFail("The default link must send a concrete copied shell request.")
        }
        XCTAssertEqual(operation, "open")
        XCTAssertEqual(target, "https://example.invalid/original?q=1")
        XCTAssertNotEqual(target, destination.absoluteString)
        XCTAssertEqual(command.windowKey, fixture.session.windowKey)

        command.reply.complete(.success(.openedURL))
        command.reject(.closed)
        let result = await XCTWaiter.fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(result, .completed)
        XCTAssertEqual(outcomes, [.opened])
        XCTAssertFalse(fixture.session.hasPendingRequests)
        XCTAssertNil(fixture.session.lastFailure)
        XCTAssertNil(ViewBuildContextScope.current)
        XCTAssertTrue(shell.calls.isEmpty)
    }

    func testActualNativeFailureAndRejectedPostStayDistinct() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let destination = try XCTUnwrap(URL(string: "mailto:fixture@example.invalid"))
        for rejectedPost in [false, true] {
            let fixture = NativeOpenURLTestFixture(rejection: rejectedPost ? .postFailed(code: 7) : nil)
            defer { fixture.close() }
            let finished = expectation(description: "typed shell failure")
            var outcomes: [BuiltInOpenURLResult] = []
            performBuiltInOpenURL(destination, action: .system, context: fixture.context) {
                outcomes.append($0)
                finished.fulfill()
            }
            XCTAssertTrue(outcomes.isEmpty)
            if !rejectedPost {
                try XCTUnwrap(fixture.sink.command(at: 0)).reply.complete(
                    .success(.failed(.native(operation: "ShellExecuteW", code: 32))))
            }
            let result = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
            let expected: NativeDialogFailure =
                rejectedPost ? .transport(.postFailed(code: 7)) : .native(operation: "ShellExecuteW", code: 32)
            XCTAssertEqual(result, .completed)
            XCTAssertEqual(outcomes, [.failed(expected)])
            XCTAssertEqual(fixture.session.lastFailure, expected)
            XCTAssertFalse(fixture.session.hasPendingRequests)
            XCTAssertEqual(fixture.sink.count, 1, "A rejected post must not retry through the legacy shell.")
            XCTAssertTrue(shell.calls.isEmpty)
        }
    }

    func testUnexpectedNativeReplyCannotBecomeOpened() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let fixture = NativeOpenURLTestFixture()
        defer { fixture.close() }
        let finished = expectation(description: "mismatched native reply")
        var outcome: BuiltInOpenURLResult?
        performBuiltInOpenURL(
            try XCTUnwrap(URL(string: "https://example.invalid/help")), action: .system, context: fixture.context
        ) {
            outcome = $0
            finished.fulfill()
        }
        try XCTUnwrap(fixture.sink.command(at: 0)).reply.complete(.success(.cancelled))
        let result = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(outcome, .failed(.unexpectedResult))
        XCTAssertTrue(shell.calls.isEmpty)
    }

    func testRevokedSessionDoesNotSubmitOrFallBackToLegacyShell() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let fixture = NativeOpenURLTestFixture()
        defer { fixture.close() }
        fixture.session.invalidate()
        var outcomes: [BuiltInOpenURLResult] = []
        performBuiltInOpenURL(
            try XCTUnwrap(URL(string: "https://example.invalid/retired")), action: .system, context: fixture.context
        ) { outcomes.append($0) }
        XCTAssertEqual(outcomes, [.revoked])
        XCTAssertEqual(fixture.sink.count, 0)
        XCTAssertFalse(fixture.session.hasPendingRequests)
        XCTAssertTrue(shell.calls.isEmpty)
    }

    func testRevocationKeepsAdmittedReplyPendingUntilNativeCompletion() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let fixture = NativeOpenURLTestFixture()
        defer { fixture.close() }
        let finished = expectation(description: "revoked terminal delivery")
        var outcomes: [BuiltInOpenURLResult] = []
        performBuiltInOpenURL(
            try XCTUnwrap(URL(string: "https://example.invalid/admitted")), action: .system, context: fixture.context
        ) {
            outcomes.append($0)
            finished.fulfill()
        }
        fixture.session.invalidate()
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertTrue(fixture.session.hasPendingRequests)
        try XCTUnwrap(fixture.sink.command(at: 0)).reply.complete(.success(.openedURL))
        let result = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(outcomes, [.revoked], "Owner revocation is not native cancellation or shell success.")
        XCTAssertFalse(fixture.session.hasPendingRequests)
        XCTAssertTrue(shell.calls.isEmpty)
    }

    func testPendingOwnerDefersNativeRequestAndResolvesTheIntentOnce() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let fixture = NativeOpenURLTestFixture()
        defer { fixture.close() }
        var deliverOwner: (@MainActor (NativeDialogSession) -> Void)?
        var ownerRequests = 0
        let context = ViewBuildContext(
            nativeDialogOwnerRequest: {
                ownerRequests += 1
                deliverOwner = $0
            },
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        let finished = expectation(description: "shell reply after owner binding")
        var outcomes: [BuiltInOpenURLResult] = []
        performBuiltInOpenURL(
            try XCTUnwrap(URL(string: "https://example.invalid/early")), action: .system, context: context
        ) {
            outcomes.append($0)
            finished.fulfill()
        }
        XCTAssertEqual(ownerRequests, 1)
        XCTAssertEqual(fixture.sink.count, 0)
        XCTAssertFalse(fixture.session.hasPendingRequests)
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertTrue(shell.calls.isEmpty)

        let resolve = try XCTUnwrap(deliverOwner)
        deliverOwner = nil
        resolve(fixture.session)
        resolve(fixture.session)
        XCTAssertEqual(fixture.sink.count, 1)
        XCTAssertTrue(outcomes.isEmpty)
        try XCTUnwrap(fixture.sink.command(at: 0)).reply.complete(.success(.openedURL))
        let result = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(outcomes, [.opened])
        XCTAssertTrue(shell.calls.isEmpty)
    }

    func testRetiredOccurrenceCannotStartShellWorkAfterOwnerBinding() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let fixture = NativeOpenURLTestFixture()
        defer { fixture.close() }
        let registry = StateMountRegistry()
        defer { registry.close() }
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        let identity = RetainedViewIdentity(segments: [.view(ObjectIdentifier(Link.self))])
        let owner = try XCTUnwrap(epoch.owner(at: identity))
        guard epoch.prepareForAdoption() else { return XCTFail("Could not prepare the retained owner.") }
        epoch.commitAdoption()
        var viewIdentity = ViewIdentityContext()
        viewIdentity.path = identity
        viewIdentity.installedOwner = owner
        var deliverOwner: (@MainActor (NativeDialogSession) -> Void)?
        let context = ViewBuildContext(
            viewIdentity: viewIdentity, nativeDialogOwnerRequest: { deliverOwner = $0 },
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        var outcomes: [BuiltInOpenURLResult] = []
        performBuiltInOpenURL(
            try XCTUnwrap(URL(string: "https://example.invalid/removed")), action: .system, context: context
        ) { outcomes.append($0) }
        XCTAssertTrue(outcomes.isEmpty)
        registry.close()
        XCTAssertFalse(owner.isLive)
        try XCTUnwrap(deliverOwner)(fixture.session)
        deliverOwner = nil
        XCTAssertEqual(outcomes, [.revoked])
        XCTAssertEqual(fixture.sink.count, 0)
        XCTAssertTrue(shell.calls.isEmpty)
    }

    func testQueuedOccurrenceIsRecheckedBeforeTheNextShellSubmission() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let fixture = NativeOpenURLTestFixture()
        defer { fixture.close() }
        let registry = StateMountRegistry()
        defer { registry.close() }
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        let identity = RetainedViewIdentity(segments: [.view(ObjectIdentifier(Link.self))])
        let owner = try XCTUnwrap(epoch.owner(at: identity))
        guard epoch.prepareForAdoption() else { return XCTFail("Could not prepare the retained owner.") }
        epoch.commitAdoption()
        var viewIdentity = ViewIdentityContext()
        viewIdentity.path = identity
        viewIdentity.installedOwner = owner
        let queuedContext = ViewBuildContext(
            viewIdentity: viewIdentity, nativeDialogSession: fixture.session,
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        let firstFinished = expectation(description: "first shell reply")
        let retired = expectation(description: "queued occurrence retired before submission")
        var outcomes: [BuiltInOpenURLResult] = []
        performBuiltInOpenURL(
            try XCTUnwrap(URL(string: "https://example.invalid/first")), action: .system, context: fixture.context
        ) {
            outcomes.append($0)
            firstFinished.fulfill()
        }
        performBuiltInOpenURL(
            try XCTUnwrap(URL(string: "https://example.invalid/queued")), action: .system, context: queuedContext
        ) {
            outcomes.append($0)
            retired.fulfill()
        }
        XCTAssertEqual(fixture.sink.count, 1)
        XCTAssertTrue(outcomes.isEmpty)
        registry.close()
        try XCTUnwrap(fixture.sink.command(at: 0)).reply.complete(.success(.openedURL))
        let result = await XCTWaiter.fulfillment(of: [firstFinished, retired], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(outcomes, [.opened, .revoked])
        XCTAssertEqual(fixture.sink.count, 1, "Retired queued input must never reach the native shell.")
        XCTAssertFalse(fixture.session.hasPendingRequests)
        XCTAssertTrue(shell.calls.isEmpty)
    }

    func testCustomHandlerResultsStayInlineWithoutSystemActionFallback() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        var ownerRequests = 0
        let context = ViewBuildContext(
            nativeDialogOwnerRequest: { _ in ownerRequests += 1 },
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        let destination = try XCTUnwrap(URL(string: "https://example.invalid/custom"))
        for expected in [OpenURLAction.Result.handled, .discarded, .systemAction] {
            var calls: [URL] = []
            let action = OpenURLAction { url in
                calls.append(url)
                return expected
            }
            XCTAssertFalse(action.isSystemAction)
            var outcome: BuiltInOpenURLResult?
            performBuiltInOpenURL(destination, action: action, context: context) { outcome = $0 }
            XCTAssertEqual(outcome, .inline(expected))
            XCTAssertEqual(calls, [destination])
        }
        XCTAssertEqual(ownerRequests, 0)
        XCTAssertTrue(shell.calls.isEmpty, "A custom .systemAction result never invokes the default shell.")
    }

    func testInjectedLegacyExecutorStaysInlineEvenWithPendingNativeOwner() async throws {
        let shell = NativeOpenURLTestShell()
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        var ownerRequests = 0
        let context = ViewBuildContext(
            nativeDialogOwnerRequest: { _ in ownerRequests += 1 },
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        let destination = try XCTUnwrap(URL(string: "https://example.invalid/legacy"))
        for succeeds in [false, true] {
            shell.result = succeeds
            var outcome: BuiltInOpenURLResult?
            performBuiltInOpenURL(destination, action: .system, context: context) { outcome = $0 }
            XCTAssertEqual(outcome, .inline(succeeds ? .handled : .discarded))
        }
        XCTAssertEqual(shell.calls.count, 2)
        XCTAssertEqual(ownerRequests, 0)
    }

    func testHeadlessAndPublicSystemCallsKeepActualSynchronousResults() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        let destination = try XCTUnwrap(URL(string: "https://example.invalid/headless"))
        XCTAssertTrue(OpenURLAction.system.isSystemAction)
        for succeeds in [false, true] {
            shell.result = succeeds
            let expected: OpenURLAction.Result = succeeds ? .handled : .discarded
            XCTAssertEqual(OpenURLAction.system(destination), expected)
            var outcome: BuiltInOpenURLResult?
            performBuiltInOpenURL(destination, action: .system, context: context) { outcome = $0 }
            XCTAssertEqual(outcome, .inline(expected))
        }
        XCTAssertEqual(shell.calls.count, 4)
    }

    func testMalformedNativeTargetFailsBeforeOwnerAcquisition() async {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        var ownerRequests = 0
        let context = ViewBuildContext(
            nativeDialogOwnerRequest: { _ in ownerRequests += 1 },
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        var outcome: BuiltInOpenURLResult?
        performBuiltInOpenURL(
            URL(fileURLWithPath: "C:/native-url-fixture/bad\nname.txt"), action: .system, context: context
        ) { outcome = $0 }
        XCTAssertEqual(outcome, .failed(.invalidShellTarget))
        XCTAssertEqual(ownerRequests, 0)
        XCTAssertTrue(shell.calls.isEmpty)
    }

    func testLinkAndHelpLinkConsumeNativeRouteWithoutLegacyExecution() async throws {
        let shell = NativeOpenURLTestShell(supportsNativeOwnerExecution: true)
        let previous = openURLShellExecutor
        openURLShellExecutor = shell
        defer { openURLShellExecutor = previous }
        let secondSubmission = expectation(description: "second built-in after first actor completion")
        let fixture = NativeOpenURLTestFixture(onSubmission: { count in
            if count == 2 { secondSubmission.fulfill() }
        })
        defer { fixture.close() }
        let destination = try XCTUnwrap(URL(string: "https://example.invalid/built-in"))
        let runtime = RetainedViewRuntime(root: ViewNode())
        defer {
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
        }
        let components = [
            Link(destination: destination) { Color.clear }.makeComponent(context: fixture.context),
            HelpLink(destination: destination).makeComponent(context: fixture.context),
        ]
        for component in components {
            let node = component.makeNode(runtime: runtime)
            runtime.root.addChild(node)
            try XCTUnwrap(firstActivation(in: node))()
        }
        XCTAssertEqual(fixture.sink.count, 1, "The next shell request waits for the prior actor completion.")
        XCTAssertTrue(fixture.session.hasPendingRequests)
        XCTAssertTrue(shell.calls.isEmpty)
        try XCTUnwrap(fixture.sink.command(at: 0)).reply.complete(.success(.openedURL))
        let result = await XCTWaiter.fulfillment(of: [secondSubmission], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(fixture.sink.count, 2)
        for index in 0..<2 {
            guard case .openURL(let operation, let target) = try XCTUnwrap(fixture.sink.command(at: index)).request
            else { return XCTFail("Each built-in must submit the resolved URL to its native owner.") }
            XCTAssertEqual(operation, "open")
            XCTAssertEqual(target, destination.absoluteString)
        }
        XCTAssertNil(ViewBuildContextScope.current)
    }

    private func firstActivation(in node: ViewNode) -> (() -> Void)? {
        if let activation = node.onActivate { return activation }
        for child in node.children {
            if let activation = firstActivation(in: child) { return activation }
        }
        return nil
    }
}

private final class NativeOpenURLTestShell: OpenURLShellExecutor {
    struct Call: Equatable {
        let operation: String
        let target: String
    }
    let supportsNativeOwnerExecution: Bool
    var result = true
    private(set) var calls: [Call] = []

    init(supportsNativeOwnerExecution: Bool = false) {
        self.supportsNativeOwnerExecution = supportsNativeOwnerExecution
    }

    func execute(operation: String, target: String) -> Bool {
        calls.append(Call(operation: operation, target: target))
        return result
    }
}

private final class NativeOpenURLTestSink: NativeWindowCommandSink {
    private let commands = Mutex<[any NativeWindowOwnerCommand]>([])
    private let rejection: NativeWindowOwnerFailure?
    private let onSubmission: (@Sendable (Int) -> Void)?

    init(rejection: NativeWindowOwnerFailure? = nil, onSubmission: (@Sendable (Int) -> Void)? = nil) {
        self.rejection = rejection
        self.onSubmission = onSubmission
    }

    var count: Int { commands.withLock { $0.count } }

    func command(at index: Int) -> NativeDialogCommand? {
        commands.withLock { $0.indices.contains(index) ? $0[index] as? NativeDialogCommand : nil }
    }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        let count = commands.withLock { value in
            value.append(command)
            return value.count
        }
        onSubmission?(count)
        if let rejection {
            command.reject(rejection)
            return .rejected(rejection)
        }
        return .accepted
    }

    func rejectAll() {
        let pending = commands.withLock { $0 }
        for command in pending { command.reject(.closed) }
    }
}

@MainActor
private final class NativeOpenURLTestFixture {
    let sink: NativeOpenURLTestSink
    let session: NativeDialogSession

    init(rejection: NativeWindowOwnerFailure? = nil, onSubmission: (@Sendable (Int) -> Void)? = nil) {
        let sink = NativeOpenURLTestSink(rejection: rejection, onSubmission: onSubmission)
        self.sink = sink
        session = NativeDialogSession(
            windowKey: NativeWindowKey(), commandSink: sink,
            executor: NativeDialogExecutor { _, _ in .failed(.unexpectedResult) })
    }

    var context: ViewBuildContext {
        ViewBuildContext(
            nativeDialogSession: session,
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
    }

    func close() {
        session.invalidate()
        sink.rejectAll()
    }
}
