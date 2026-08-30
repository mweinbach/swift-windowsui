import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The injected operation suspends on owned continuations. Positive start,
/// cancellation, phase and host-completion signals establish each boundary;
/// these tests do not use sleeps or executor yields as evidence.
@MainActor
final class AsyncImageLifecycleTests: XCTestCase {
    private func url(_ name: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://async-image.invalid/\(name).png"))
    }

    private func bitmap(_ value: UInt8) -> BitmapSurface {
        BitmapSurface(
            width: 12, height: 8, bytesPerRow: 48,
            pixels: Data(repeating: value, count: 384), format: .bgra8Straight)
    }

    private func presentation(
        _ url: URL?, service: AsyncImageService, scale: Double = 1,
        transaction: Transaction = Transaction()
    ) -> AsyncImagePresentation {
        AsyncImagePresentation(
            source: AsyncImageSource(url: url, service: service), scale: scale, transaction: transaction)
    }

    private func assertEmpty(
        _ phase: AsyncImagePhase, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .empty = phase else {
            return XCTFail("Expected an empty phase", file: file, line: line)
        }
    }

    private func imageNode(
        _ phase: AsyncImagePhase, file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        let image = try XCTUnwrap(phase.image, file: file, line: line)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 200, height: 200) }, invalidateHandler: {})
        return image.makeComponent(context: context).makeNode(runtime: runtime)
    }

    private func phaseBitmap(
        _ phase: AsyncImagePhase, file: StaticString = #filePath, line: UInt = #line
    ) throws -> BitmapSurface {
        try XCTUnwrap(imageNode(phase, file: file, line: line).bitmapSurface, file: file, line: line)
    }

    private func started(
        _ fixture: AsyncImageLifecycleFixture, url: URL, occurrence: Int = 1
    ) async throws -> AsyncImageLifecycleGate.Request {
        let ready = expectation(description: "operation \(url.lastPathComponent) #\(occurrence) owns its continuation")
        fixture.gate.whenStarted(url, occurrence: occurrence, expectation: ready)
        await fulfillment(of: [ready], timeout: 5)
        let matches = fixture.gate.requests.filter { $0.url == url }
        guard matches.count >= occurrence else { throw AsyncImageLifecycleFixtureError.missingRequest }
        return matches[occurrence - 1]
    }

    private func expectSuccess(_ loader: AsyncImageLoader) -> (XCTestExpectation, AnyCancellable) {
        let succeeded = expectation(description: "loader published an image")
        var delivered = false
        let token = loader.$phase.sink { phase in
            if phase.image != nil, !delivered {
                delivered = true
                succeeded.fulfill()
            }
        }
        return (succeeded, token)
    }

    private func assertCompletedSourceIsReloadedAfterAdoption(_ intermediate: URL?) async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let source = try url("completed-a")
        let loader = AsyncImageLoader()
        let first = presentation(source, service: fixture.service)
        loader.configure(first)
        let firstRun = fixture.run(loader, presentation: first)
        let firstRequest = try await started(fixture, url: source)
        let oldPixels = bitmap(10)
        XCTAssertTrue(fixture.gate.resolve(firstRequest.id, with: .success(oldPixels)))
        await fulfillment(of: [firstRun.completed], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.visiblePhase(for: first)).contentKey, oldPixels.contentKey)

        // The intermediate source is adopted but never runs. Construction alone
        // would not revoke A; configure is the explicit adoption boundary here.
        loader.configure(presentation(intermediate, service: fixture.service))
        let returned = presentation(source, service: fixture.service)
        loader.configure(returned)
        assertEmpty(loader.visiblePhase(for: returned))
        let nextRun = fixture.run(loader, presentation: returned)
        let nextRequest = try await started(fixture, url: source, occurrence: 2)
        let newPixels = bitmap(90)
        XCTAssertTrue(fixture.gate.resolve(nextRequest.id, with: .success(newPixels)))
        await fulfillment(of: [nextRun.completed], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, newPixels.contentKey)
        XCTAssertEqual(fixture.gate.requests.map(\.url), [source, source])
    }

    func testNilSourcePublishesEmptyWithoutStartingTheService() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let loader = AsyncImageLoader()
        let next = presentation(nil, service: fixture.service)
        loader.configure(next)
        let run = fixture.run(loader, presentation: next)
        await fulfillment(of: [run.completed], timeout: 5)
        assertEmpty(loader.phase)
        assertEmpty(loader.visiblePhase(for: next))
        XCTAssertTrue(fixture.gate.requests.isEmpty)
        XCTAssertEqual(fixture.service.snapshot.activeRequests, 0)
    }

    func testCompletedAAdoptedBThenAdoptedARequiresANewRequestWithoutRunningB() async throws {
        try await assertCompletedSourceIsReloadedAfterAdoption(url("adopted-b"))
    }

    func testCompletedAAdoptedNilThenAdoptedARequiresANewRequestWithoutRunningNil() async throws {
        try await assertCompletedSourceIsReloadedAfterAdoption(nil)
    }

    func testRepeatedImperativeNilClearsManuallyAssignedPublicPhases() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let loader = AsyncImageLoader(service: fixture.service)
        loader.load(url: nil)
        loader.phase = .failure(AsyncImageLifecycleFixtureError.failed)
        loader.load(url: nil)
        assertEmpty(loader.phase)
        loader.phase = .success(Image(bitmap: bitmap(1)))
        loader.load(url: nil, scale: 2)
        assertEmpty(loader.phase)
        XCTAssertTrue(fixture.gate.requests.isEmpty)
    }

    func testImperativeSameURLReusesCompletedPixelsWhenScaleChanges() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let source = try url("same")
        let loader = AsyncImageLoader(service: fixture.service)
        let (succeeded, token) = expectSuccess(loader)
        defer { token.cancel() }
        loader.load(url: source)
        let request = try await started(fixture, url: source)
        let original = bitmap(21)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(original)))
        await fulfillment(of: [succeeded], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, original.contentKey)
        loader.load(url: source, scale: 2)
        let scaled = try imageNode(loader.phase)
        XCTAssertEqual(scaled.bitmapSurface?.contentKey, original.contentKey)
        XCTAssertEqual(scaled.intrinsicContentSize(), Size(width: 6, height: 4))
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testURLReplacementKeepsTheNewImageAfterAnOldOperationReturnsSuccess() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let firstURL = try url("a")
        let secondURL = try url("b")
        let loader = AsyncImageLoader()
        let first = presentation(firstURL, service: fixture.service)
        loader.configure(first)
        let firstRun = fixture.run(loader, presentation: first)
        let oldRequest = try await started(fixture, url: firstURL)
        let second = presentation(secondURL, service: fixture.service)
        loader.configure(second)
        XCTAssertTrue(oldRequest.cancellation.isCancelled)
        assertEmpty(loader.visiblePhase(for: second))
        let secondRun = fixture.run(loader, presentation: second)
        let currentRequest = try await started(fixture, url: secondURL)
        let current = bitmap(42)
        XCTAssertTrue(fixture.gate.resolve(currentRequest.id, with: .success(current)))
        await fulfillment(of: [secondRun.completed], timeout: 5)
        XCTAssertTrue(fixture.gate.resolve(oldRequest.id, with: .success(bitmap(11))))
        await fulfillment(of: [firstRun.completed], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, current.contentKey)
        assertEmpty(loader.visiblePhase(for: first))
        XCTAssertEqual(fixture.gate.requests.map(\.url), [firstURL, secondURL])
    }

    func testURLReplacementSuppressesAnOldOperationFailure() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let firstURL = try url("failed-old")
        let secondURL = try url("current")
        let loader = AsyncImageLoader()
        let first = presentation(firstURL, service: fixture.service)
        loader.configure(first)
        let firstRun = fixture.run(loader, presentation: first)
        let oldRequest = try await started(fixture, url: firstURL)
        let second = presentation(secondURL, service: fixture.service)
        loader.configure(second)
        let secondRun = fixture.run(loader, presentation: second)
        let currentRequest = try await started(fixture, url: secondURL)
        XCTAssertTrue(fixture.gate.resolve(oldRequest.id, with: .failure(AsyncImageLifecycleFixtureError.failed)))
        await fulfillment(of: [firstRun.completed], timeout: 5)
        assertEmpty(loader.visiblePhase(for: second))
        XCTAssertNil(loader.phase.error)
        let current = bitmap(51)
        XCTAssertTrue(fixture.gate.resolve(currentRequest.id, with: .success(current)))
        await fulfillment(of: [secondRun.completed], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, current.contentKey)
    }

    func testNilRevokesAnActiveRequestAndItsLateReplyStaysEmpty() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let source = try url("nil-replacement")
        let loader = AsyncImageLoader()
        let active = presentation(source, service: fixture.service)
        loader.configure(active)
        let run = fixture.run(loader, presentation: active)
        let request = try await started(fixture, url: source)
        let absent = presentation(nil, service: fixture.service)
        loader.configure(absent)
        let nilRun = fixture.run(loader, presentation: absent)
        await fulfillment(of: [nilRun.completed], timeout: 5)
        XCTAssertTrue(request.cancellation.isCancelled)
        assertEmpty(loader.phase)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(bitmap(18))))
        await fulfillment(of: [run.completed], timeout: 5)
        assertEmpty(loader.phase)
        assertEmpty(loader.visiblePhase(for: absent))
    }

    func testTheSameURLOnADifferentServiceHasDifferentRequestIdentity() async throws {
        let firstFixture = AsyncImageLifecycleFixture()
        let secondFixture = AsyncImageLifecycleFixture()
        defer {
            firstFixture.close()
            secondFixture.close()
        }
        let source = try url("service-change")
        let loader = AsyncImageLoader()
        let first = presentation(source, service: firstFixture.service)
        loader.configure(first)
        let firstRun = firstFixture.run(loader, presentation: first)
        let oldRequest = try await started(firstFixture, url: source)
        let second = presentation(source, service: secondFixture.service)
        XCTAssertNotEqual(first.source, second.source)
        loader.configure(second)
        XCTAssertTrue(oldRequest.cancellation.isCancelled)
        let secondRun = secondFixture.run(loader, presentation: second)
        let currentRequest = try await started(secondFixture, url: source)
        let current = bitmap(61)
        XCTAssertTrue(secondFixture.gate.resolve(currentRequest.id, with: .success(current)))
        XCTAssertTrue(firstFixture.gate.resolve(oldRequest.id, with: .success(bitmap(3))))
        await fulfillment(of: [firstRun.completed, secondRun.completed], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, current.contentKey)
    }

    func testActiveRequestUsesLatestAdoptedScaleAndFullTransactionWithoutRestart() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let source = try url("presentation")
        let loader = AsyncImageLoader()
        let first = presentation(
            source, service: fixture.service, transaction: Transaction(animation: .linear(duration: 5)))
        loader.configure(first)
        let run = fixture.run(loader, presentation: first)
        let request = try await started(fixture, url: source)
        var transaction = Transaction(animation: .linear(duration: 1.25))
        transaction.disablesAnimations = true
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        let next = presentation(source, service: fixture.service, scale: 2, transaction: transaction)
        XCTAssertEqual(first.source, next.source)
        loader.configure(next)
        let reusedRun = fixture.run(loader, presentation: next)
        await fulfillment(of: [reusedRun.completed], timeout: 5)
        XCTAssertFalse(request.cancellation.isCancelled)
        var deliveredTransaction: Transaction?
        let token = loader.$phase.sink { phase in
            if phase.image != nil { deliveredTransaction = currentTransaction }
        }
        defer { token.cancel() }
        let original = bitmap(27)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(original)))
        await fulfillment(of: [run.completed], timeout: 5)
        let image = try imageNode(loader.phase)
        XCTAssertEqual(image.bitmapSurface?.contentKey, original.contentKey)
        XCTAssertEqual(image.intrinsicContentSize(), Size(width: 6, height: 4))
        XCTAssertEqual(deliveredTransaction?.animation?.duration, 1.25)
        XCTAssertEqual(deliveredTransaction?.disablesAnimations, true)
        XCTAssertEqual(deliveredTransaction?.isContinuous, true)
        XCTAssertEqual(deliveredTransaction?.scrollTargetAnchor, .bottom)
        XCTAssertEqual(deliveredTransaction?.tracksVelocity, true)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testInspectingAnUnadoptedPresentationDoesNotRevokeTheCurrentRequest() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let source = try url("adopted")
        let loader = AsyncImageLoader()
        let adopted = presentation(source, service: fixture.service)
        loader.configure(adopted)
        let run = fixture.run(loader, presentation: adopted)
        let request = try await started(fixture, url: source)
        let candidate = presentation(try url("candidate"), service: fixture.service)
        assertEmpty(loader.visiblePhase(for: candidate))
        XCTAssertFalse(request.cancellation.isCancelled)
        let original = bitmap(17)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(original)))
        await fulfillment(of: [run.completed], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.visiblePhase(for: adopted)).contentKey, original.contentKey)
        assertEmpty(loader.visiblePhase(for: candidate))
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testReentryFromEmptyPublicationStartsOnlyTheSuccessorURL() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let firstURL = try url("reentered-before-start")
        let secondURL = try url("reentrant-successor")
        let loader = AsyncImageLoader(service: fixture.service)
        var armed = false
        var reentries = 0
        let token = loader.$phase.sink { [weak loader] phase in
            guard armed, case .empty = phase else { return }
            armed = false
            reentries += 1
            loader?.load(url: secondURL)
        }
        defer { token.cancel() }
        let (succeeded, successToken) = expectSuccess(loader)
        defer { successToken.cancel() }
        armed = true
        loader.load(url: firstURL)
        let request = try await started(fixture, url: secondURL)
        XCTAssertEqual(reentries, 1)
        XCTAssertEqual(fixture.gate.requests.map(\.url), [secondURL])
        let current = bitmap(35)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(current)))
        await fulfillment(of: [succeeded], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, current.contentKey)
    }

    func testReentryFromSuccessPublicationDoesNotLoseTheSuccessorInvocation() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let firstURL = try url("success-before-reentry")
        let secondURL = try url("success-after-reentry")
        let loader = AsyncImageLoader(service: fixture.service)
        var successCount = 0
        let finished = expectation(description: "successor published after success callback reentry")
        let token = loader.$phase.sink { [weak loader] phase in
            guard phase.image != nil else { return }
            successCount += 1
            if successCount == 1 { loader?.load(url: secondURL) }
            if successCount == 2 { finished.fulfill() }
        }
        defer { token.cancel() }
        loader.load(url: firstURL)
        let firstRequest = try await started(fixture, url: firstURL)
        XCTAssertTrue(fixture.gate.resolve(firstRequest.id, with: .success(bitmap(19))))
        let secondRequest = try await started(fixture, url: secondURL)
        assertEmpty(loader.phase)
        let current = bitmap(78)
        XCTAssertTrue(fixture.gate.resolve(secondRequest.id, with: .success(current)))
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(successCount, 2)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, current.contentKey)
    }

    func testCancelledRunStaysEmptyAndCanRestartTheSameURL() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let source = try url("cancel-and-restart")
        let loader = AsyncImageLoader()
        let next = presentation(source, service: fixture.service)
        loader.configure(next)
        let firstRun = fixture.run(loader, presentation: next)
        let firstRequest = try await started(fixture, url: source)
        let cancelled = expectation(description: "the first operation received actual cancellation")
        let registration = firstRequest.cancellation.register { cancelled.fulfill() }
        defer { firstRequest.cancellation.unregister(registration) }
        firstRun.task.cancel()
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertTrue(fixture.gate.resolve(firstRequest.id, with: .success(bitmap(5))))
        await fulfillment(of: [firstRun.completed], timeout: 5)
        assertEmpty(loader.phase)
        XCTAssertNil(loader.phase.error)
        let secondRun = fixture.run(loader, presentation: next)
        let secondRequest = try await started(fixture, url: source, occurrence: 2)
        XCTAssertFalse(secondRequest.cancellation.isCancelled)
        let current = bitmap(91)
        XCTAssertTrue(fixture.gate.resolve(secondRequest.id, with: .success(current)))
        await fulfillment(of: [secondRun.completed], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, current.contentKey)
    }

    func testTaskCancelledBeforeItsMainActorActionDoesNotStartTheService() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let loader = AsyncImageLoader()
        let next = presentation(try url("cancel-before-action"), service: fixture.service)
        loader.configure(next)
        let run = fixture.run(loader, presentation: next)
        // Both operations occur in this synchronous MainActor turn; run's
        // action cannot enter until this test first suspends below.
        run.task.cancel()
        await fulfillment(of: [run.completed], timeout: 5)
        XCTAssertTrue(fixture.gate.requests.isEmpty)
        assertEmpty(loader.phase)
    }

    func testTerminalFailureDoesNotRefetchForAnUnchangedSource() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let source = try url("terminal-failure")
        let loader = AsyncImageLoader()
        let first = presentation(source, service: fixture.service)
        loader.configure(first)
        let run = fixture.run(loader, presentation: first)
        let request = try await started(fixture, url: source)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .failure(AsyncImageLifecycleFixtureError.failed)))
        await fulfillment(of: [run.completed], timeout: 5)
        XCTAssertEqual(loader.phase.error as? AsyncImageLifecycleFixtureError, .failed)
        let next = presentation(source, service: fixture.service, scale: 2)
        loader.configure(next)
        let reusedRun = fixture.run(loader, presentation: next)
        await fulfillment(of: [reusedRun.completed], timeout: 5)
        XCTAssertEqual(loader.visiblePhase(for: next).error as? AsyncImageLifecycleFixtureError, .failed)
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testCoordinatorsOwnDifferentServicesAndCloseOnlyTheirOwnService() async throws {
        let first = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        let second = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        defer {
            first.close()
            second.close()
        }
        let firstService = try XCTUnwrap(first.asyncImageService)
        let secondService = try XCTUnwrap(second.asyncImageService)
        XCTAssertTrue(first.asyncImageService === firstService)
        XCTAssertFalse(firstService === secondService)
        first.close()
        XCTAssertTrue(firstService.snapshot.isClosed)
        XCTAssertNil(first.asyncImageService)
        XCTAssertFalse(secondService.snapshot.isClosed)
        XCTAssertTrue(second.asyncImageService === secondService)
    }

    func testCancellationDuringInitialPublicationAllowsSynchronousSameSourceRestart() async throws {
        let fixture = AsyncImageLifecycleFixture()
        defer { fixture.close() }
        let source = try url("initial-publication-cancellation")
        let loader = AsyncImageLoader(service: fixture.service)
        let next = presentation(source, service: fixture.service)
        loader.configure(next)
        var firstRun: AsyncImageLifecycleFixture.Run?
        var armed = false
        var reentries = 0
        let token = loader.$phase.sink { phase in
            guard armed, case .empty = phase else { return }
            armed = false
            reentries += 1
            firstRun?.task.cancel()
            // Cancellation must revoke the pre-created invocation token before
            // this synchronous call. Waiting for service.load would be too late:
            // the successor would be mistaken for an already-active request.
            loader.load(url: source)
        }
        defer { token.cancel() }
        let (succeeded, successToken) = expectSuccess(loader)
        defer { successToken.cancel() }
        armed = true
        firstRun = fixture.run(loader, presentation: next)
        let currentRequest = try await started(fixture, url: source)
        XCTAssertEqual(reentries, 1)
        XCTAssertTrue(try XCTUnwrap(firstRun).task.isCancelled)
        XCTAssertFalse(currentRequest.cancellation.isCancelled)
        let current = bitmap(83)
        XCTAssertTrue(fixture.gate.resolve(currentRequest.id, with: .success(current)))
        await fulfillment(of: [try XCTUnwrap(firstRun).completed, succeeded], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, current.contentKey)
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testMountedDefaultEmptyContentKeepsATaskTargetUntilPixelsArrive() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let source = try url("default-empty")
        let host = AsyncImageLifecycleMountedHost(service: fixture.service) { AnyView(AsyncImage(url: source)) }
        defer {
            host.close()
            fixture.close()
        }
        XCTAssertTrue(fixture.gate.requests.isEmpty, "Building a provisional tree must not start its operation")
        XCTAssertFalse(host.runtime.root.children.isEmpty, "The empty phase still needs a retained task target")
        host.render()
        let request = try await started(fixture, url: source)
        let loader = try XCTUnwrap(host.probe.loaders.last)
        let (succeeded, token) = expectSuccess(loader)
        defer { token.cancel() }
        let original = bitmap(40)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(original)))
        await fulfillment(of: [succeeded], timeout: 5)
        host.reload()
        host.render()
        XCTAssertEqual(host.nodes.compactMap(\.bitmapSurface).map(\.contentKey), [original.contentKey])
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testMountedRebuildOfAnActiveSourcePreservesItsLoaderAndRequest() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let source = try url("mounted-rebuild")
        let host = AsyncImageLifecycleMountedHost(service: fixture.service) { AnyView(AsyncImage(url: source)) }
        defer {
            host.close()
            fixture.close()
        }
        host.render()
        let request = try await started(fixture, url: source)
        let loader = try XCTUnwrap(host.probe.loaders.last)
        let (succeeded, token) = expectSuccess(loader)
        defer { token.cancel() }
        host.reload()
        host.render()
        XCTAssertTrue(host.probe.loaders.last === loader)
        XCTAssertFalse(request.cancellation.isCancelled)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(bitmap(30))))
        await fulfillment(of: [succeeded], timeout: 5)
        host.reload()
        host.render()
        XCTAssertTrue(host.probe.loaders.last === loader)
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testMountedScaleOnlyAdoptionReusesTheActiveRequestAndOriginalPixels() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let source = try url("mounted-scale")
        var scale = 1.0
        let host = AsyncImageLifecycleMountedHost(service: fixture.service) {
            AnyView(AsyncImage(url: source, scale: scale))
        }
        defer {
            host.close()
            fixture.close()
        }
        host.render()
        let request = try await started(fixture, url: source)
        let loader = try XCTUnwrap(host.probe.loaders.last)
        let (succeeded, token) = expectSuccess(loader)
        defer { token.cancel() }
        scale = 2
        host.reload()
        host.render()
        XCTAssertFalse(request.cancellation.isCancelled)
        let original = bitmap(64)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(original)))
        await fulfillment(of: [succeeded], timeout: 5)
        let phaseNode = try imageNode(loader.phase)
        XCTAssertEqual(phaseNode.bitmapSurface?.contentKey, original.contentKey)
        XCTAssertEqual(phaseNode.intrinsicContentSize(), Size(width: 6, height: 4))
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testDefaultDataListCanStartAnImageWithAnEmptyDefaultPlaceholder() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let source = try url("list-empty")
        let host = AsyncImageLifecycleMountedHost(service: fixture.service) {
            AnyView(List([1], id: \.self) { _ in AsyncImage(url: source) })
        }
        defer {
            host.close()
            fixture.close()
        }
        host.render()
        let request = try await started(fixture, url: source)
        let loader = try XCTUnwrap(host.probe.loaders.last)
        let (succeeded, token) = expectSuccess(loader)
        defer { token.cancel() }
        let original = bitmap(81)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(original)))
        await fulfillment(of: [succeeded], timeout: 5)
        host.reload()
        host.render()
        XCTAssertTrue(host.nodes.contains { $0.bitmapSurface?.contentKey == original.contentKey })
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }

    func testCopiedSiblingImagesOwnDifferentLoadersAndIndependentPhases() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let source = try url("copied-siblings")
        let image = AsyncImage(url: source)
        let host = AsyncImageLifecycleMountedHost(service: fixture.service) {
            AnyView(
                HStack {
                    image
                    image
                })
        }
        defer {
            host.close()
            fixture.close()
        }
        host.render()
        let firstRequest = try await started(fixture, url: source)
        let secondRequest = try await started(fixture, url: source, occurrence: 2)
        let loaders = host.probe.loaders
        XCTAssertEqual(loaders.count, 2)
        let firstLoader = try XCTUnwrap(loaders.first)
        let secondLoader = try XCTUnwrap(loaders.last)
        XCTAssertFalse(firstLoader === secondLoader)
        let oneSucceeded = expectation(description: "exactly one copied sibling published its result")
        let bothSucceeded = expectation(description: "both copied siblings published separate results")
        var published = Set<ObjectIdentifier>()
        let tokens = loaders.map { loader in
            loader.$phase.sink { phase in
                guard phase.image != nil, published.insert(ObjectIdentifier(loader)).inserted else { return }
                if published.count == 1 { oneSucceeded.fulfill() }
                if published.count == 2 { bothSucceeded.fulfill() }
            }
        }
        defer { for token in tokens { token.cancel() } }
        let firstPixels = bitmap(12)
        let secondPixels = bitmap(99)
        XCTAssertTrue(fixture.gate.resolve(firstRequest.id, with: .success(firstPixels)))
        await fulfillment(of: [oneSucceeded], timeout: 5)
        XCTAssertEqual(loaders.filter { $0.phase.image != nil }.count, 1)
        XCTAssertEqual(loaders.filter { $0.phase.image == nil }.count, 1)
        XCTAssertTrue(fixture.gate.resolve(secondRequest.id, with: .success(secondPixels)))
        await fulfillment(of: [bothSucceeded], timeout: 5)
        let keys = try loaders.map { try phaseBitmap($0.phase).contentKey }
        XCTAssertEqual(Set(keys), Set([firstPixels.contentKey, secondPixels.contentKey]))
        XCTAssertEqual(fixture.gate.requests.count, 2)
    }

    func testClosingOneHostDoesNotCancelTheSameURLInAnotherHost() async throws {
        let firstFixture = AsyncImageLifecycleFixture()
        let secondFixture = AsyncImageLifecycleFixture()
        let source = try url("two-hosts")
        let first = AsyncImageLifecycleMountedHost(service: firstFixture.service) { AnyView(AsyncImage(url: source)) }
        let second = AsyncImageLifecycleMountedHost(service: secondFixture.service) { AnyView(AsyncImage(url: source)) }
        defer {
            first.close()
            second.close()
            firstFixture.close()
            secondFixture.close()
        }
        first.render()
        second.render()
        let firstRequest = try await started(firstFixture, url: source)
        let secondRequest = try await started(secondFixture, url: source)
        let firstLoader = try XCTUnwrap(first.probe.loaders.last)
        let secondLoader = try XCTUnwrap(second.probe.loaders.last)
        XCTAssertFalse(firstLoader === secondLoader)
        let cancelled = expectation(description: "closing the first host cancelled its own request")
        let registration = firstRequest.cancellation.register { cancelled.fulfill() }
        defer { firstRequest.cancellation.unregister(registration) }
        first.close()
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertFalse(secondRequest.cancellation.isCancelled)
        XCTAssertFalse(secondFixture.service.snapshot.isClosed)
        let (succeeded, token) = expectSuccess(secondLoader)
        defer { token.cancel() }
        let current = bitmap(77)
        XCTAssertTrue(secondFixture.gate.resolve(secondRequest.id, with: .success(current)))
        await fulfillment(of: [succeeded], timeout: 5)
        XCTAssertEqual(try phaseBitmap(secondLoader.phase).contentKey, current.contentKey)
        assertEmpty(firstLoader.phase)
    }

    func testRemovalAndReinsertionCreatesANewMountedAttemptForTheSameURL() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let source = try url("reinserted")
        var visible = true
        let host = AsyncImageLifecycleMountedHost(service: fixture.service) {
            AnyView(VStack { if visible { AsyncImage(url: source) } })
        }
        defer {
            host.close()
            fixture.close()
        }
        host.render()
        let originalRequest = try await started(fixture, url: source)
        let originalLoader = try XCTUnwrap(host.probe.loaders.last)
        let cancelled = expectation(description: "unmount cancelled the old request")
        let registration = originalRequest.cancellation.register { cancelled.fulfill() }
        defer { originalRequest.cancellation.unregister(registration) }
        visible = false
        host.reload()
        await fulfillment(of: [cancelled], timeout: 5)
        visible = true
        host.reload()
        let replacementLoader = try XCTUnwrap(host.probe.loaders.last)
        XCTAssertFalse(replacementLoader === originalLoader)
        host.render()
        let replacementRequest = try await started(fixture, url: source, occurrence: 2)
        let (succeeded, token) = expectSuccess(replacementLoader)
        defer { token.cancel() }
        let current = bitmap(62)
        XCTAssertTrue(fixture.gate.resolve(originalRequest.id, with: .success(bitmap(6))))
        XCTAssertTrue(fixture.gate.resolve(replacementRequest.id, with: .success(current)))
        await fulfillment(of: [succeeded], timeout: 5)
        XCTAssertEqual(try phaseBitmap(replacementLoader.phase).contentKey, current.contentKey)
        assertEmpty(originalLoader.phase)
    }

    func testClosingAMountedHostRevokesWorkButDoesNotCloseABorrowedService() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let source = try url("close")
        let host = AsyncImageLifecycleMountedHost(service: fixture.service) { AnyView(AsyncImage(url: source)) }
        defer {
            host.close()
            fixture.close()
        }
        host.render()
        let request = try await started(fixture, url: source)
        let cancelled = expectation(description: "host close reached the owned operation's cancellation token")
        let registration = request.cancellation.register { cancelled.fulfill() }
        defer { request.cancellation.unregister(registration) }
        host.close()
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertTrue(host.coordinator.registry.isClosed)
        XCTAssertTrue(host.runtime.root.children.isEmpty)
        XCTAssertFalse(fixture.service.snapshot.isClosed, "An injected environment service is borrowed")
        XCTAssertEqual(fixture.service.snapshot.activeRequests, 1, "Cancellation must not release an active slot early")
    }

    func testSupersededMountedCandidateDoesNotCancelTheAdoptedSource() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let originalURL = try url("adopted-before-candidate")
        let candidateURL = try url("abandoned-candidate")
        var source = originalURL
        let probe = AsyncImageLifecycleMountedProbe()
        let host = AsyncImageLifecycleMountedHost(service: fixture.service, probe: probe) {
            AnyView(
                AsyncImage(url: source) { _ in
                    AsyncImageLifecycleConstructionLeaf(probe: probe)
                })
        }
        defer {
            host.close()
            fixture.close()
        }
        host.render()
        let request = try await started(fixture, url: originalURL)
        let loader = try XCTUnwrap(probe.loaders.last)
        let (succeeded, token) = expectSuccess(loader)
        defer { token.cancel() }
        var reentries = 0
        probe.onConstruct = { [weak host, weak probe] in
            probe?.onConstruct = nil
            reentries += 1
            source = originalURL
            host?.reload()
        }
        source = candidateURL
        host.reload()
        XCTAssertEqual(reentries, 1)
        XCTAssertFalse(host.componentHost.isBuilding)
        XCTAssertFalse(request.cancellation.isCancelled)
        XCTAssertTrue(probe.loaders.last === loader)
        let current = bitmap(44)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(current)))
        await fulfillment(of: [succeeded], timeout: 5)
        XCTAssertEqual(try phaseBitmap(loader.phase).contentKey, current.contentKey)
        XCTAssertEqual(fixture.gate.requests.map(\.url), [originalURL])
    }

    func testWindowHostAutomaticallyRebuildsObservedImageCompletionWithoutManualReload() async throws {
        let fixture = AsyncImageLifecycleFixture()
        let source = try url("window-observation")
        let harness = AsyncImageLifecycleWindowHarness(
            AsyncImage(url: source).environment(\.asyncImageService, fixture.service))
        defer {
            harness.close()
            fixture.close()
        }
        let adopted = expectation(description: "the real host adopted the image through object observation")
        let completed = expectation(description: "the real host completed its observed reload task")
        var sawAdoption = false
        var sawCompletion = false
        harness.host.onReloadContentCompleted = { [weak harness] in
            guard let harness, harness.nodes.contains(where: { $0.bitmapSurface != nil }), !sawAdoption else { return }
            sawAdoption = true
            adopted.fulfill()
        }
        harness.host.onObservedObjectReloadTaskCompleted = { [weak harness] didReload in
            guard let harness, didReload, harness.nodes.contains(where: { $0.bitmapSurface != nil }), !sawCompletion
            else { return }
            sawCompletion = true
            completed.fulfill()
        }
        let request = try await started(fixture, url: source)
        let original = bitmap(38)
        XCTAssertTrue(fixture.gate.resolve(request.id, with: .success(original)))
        // No host.reloadContent(), state write, frame tick, or custom observer
        // callback drives this rebuild. The production host subscription does.
        await fulfillment(of: [adopted, completed], timeout: 5)
        XCTAssertGreaterThan(harness.host.scheduledReloadCount, 0)
        XCTAssertGreaterThan(harness.host.executedReloadCount, 0)
        XCTAssertGreaterThan(harness.host.completedObservedObjectReloadTaskCount, 0)
        XCTAssertTrue(harness.nodes.contains { $0.bitmapSurface?.contentKey == original.contentKey })
        let priorFrames = harness.renderer.renderedFrames.count
        harness.host.windowNeedsDisplay(harness.window)
        XCTAssertGreaterThan(harness.renderer.renderedFrames.count, priorFrames)
        XCTAssertEqual(fixture.gate.requests.count, 1)
    }
}

private enum AsyncImageLifecycleFixtureError: Error, Equatable {
    case failed
    case missingRequest
}

/// Only the lock-protected continuation ledger crosses executors. It owns no
/// view or main-actor callback. Cancellation is deliberately noncooperative so
/// tests can deliver an old result after revocation and exercise real admission.
private final class AsyncImageLifecycleGate: @unchecked Sendable {
    struct Request: Sendable {
        let id: Int
        let url: URL
        let cancellation: AsyncImageCancellation
    }

    private struct Waiter {
        let url: URL
        let occurrence: Int
        let expectation: XCTestExpectation
    }

    private let lock = NSLock()
    private var recorded: [Request] = []
    private var pending: [Int: CheckedContinuation<BitmapSurface, any Error>] = [:]
    private var waiters: [Waiter] = []
    private var closed = false

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func perform(_ url: URL, cancellation: AsyncImageCancellation) async throws -> BitmapSurface {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let request = Request(id: recorded.count, url: url, cancellation: cancellation)
            recorded.append(request)
            let isClosed = closed
            if !isClosed { pending[request.id] = continuation }
            let ready = waiters.filter { waiter in
                recorded.filter { $0.url == waiter.url }.count >= waiter.occurrence
            }
            waiters.removeAll { waiter in
                recorded.filter { $0.url == waiter.url }.count >= waiter.occurrence
            }
            lock.unlock()
            // Readiness means that the exact operation owns its continuation,
            // not merely that a detached task was queued.
            for waiter in ready { waiter.expectation.fulfill() }
            if isClosed { continuation.resume(throwing: CancellationError()) }
        }
    }

    func whenStarted(_ url: URL, occurrence: Int, expectation: XCTestExpectation) {
        lock.lock()
        let ready = recorded.filter { $0.url == url }.count >= occurrence
        if !ready { waiters.append(Waiter(url: url, occurrence: occurrence, expectation: expectation)) }
        lock.unlock()
        if ready { expectation.fulfill() }
    }

    func resolve(_ id: Int, with result: Result<BitmapSurface, any Error>) -> Bool {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }

    func close() {
        lock.lock()
        closed = true
        let continuations = Array(pending.values)
        pending.removeAll()
        waiters.removeAll()
        lock.unlock()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
private final class AsyncImageLifecycleFixture {
    struct Run {
        let task: Task<Void, Never>
        let completed: XCTestExpectation
    }

    let gate: AsyncImageLifecycleGate
    let service: AsyncImageService
    private var tasks: [Task<Void, Never>] = []

    init() {
        let gate = AsyncImageLifecycleGate()
        self.gate = gate
        service = AsyncImageService { url, cancellation in try await gate.perform(url, cancellation: cancellation) }
    }

    func run(_ loader: AsyncImageLoader, presentation: AsyncImagePresentation) -> Run {
        let service = service
        let completed = XCTestExpectation(description: "loader.run returned after its final publication decision")
        let task = Task { @MainActor in
            await loader.run(presentation, service: service)
            completed.fulfill()
        }
        tasks.append(task)
        return Run(task: task, completed: completed)
    }

    func close() {
        for task in tasks { task.cancel() }
        service.close()
        gate.close()
    }
}

@MainActor
private final class AsyncImageLifecycleWeakLoader {
    weak var value: AsyncImageLoader?

    init(_ value: AsyncImageLoader) { self.value = value }
}

@MainActor
private final class AsyncImageLifecycleMountedProbe {
    private var known = Set<ObjectIdentifier>()
    private var references: [AsyncImageLifecycleWeakLoader] = []
    var onConstruct: (@MainActor () -> Void)?

    var loaders: [AsyncImageLoader] { references.compactMap(\.value) }

    func observe(_ object: any ObservableObject) {
        guard let loader = object as? AsyncImageLoader, known.insert(ObjectIdentifier(loader)).inserted else { return }
        references.append(AsyncImageLifecycleWeakLoader(loader))
    }
}

/// This harness isolates retained adoption and task ownership. Phase rendering
/// is reloaded explicitly here; the separate WindowHarness test below qualifies
/// the actual production host's automatic object-observation path.
@MainActor
private final class AsyncImageLifecycleMountedHost {
    let runtime: RetainedViewRuntime
    let componentHost: ComponentHost
    let coordinator: StateMountCoordinator
    let probe: AsyncImageLifecycleMountedProbe
    private var isClosed = false

    init(
        service: AsyncImageService, probe: AsyncImageLifecycleMountedProbe = AsyncImageLifecycleMountedProbe(),
        content: @escaping @MainActor () -> AnyView
    ) {
        let size = Size(width: 300, height: 200)
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 300, height: 200)))
        let componentHost = ComponentHost(runtime: runtime)
        let coordinator = StateMountCoordinator(
            invalidate: { [weak componentHost] in componentHost?.reload() },
            observeObject: { [weak probe] in probe?.observe($0) },
            updateObservedObjects: { _, _, _ in })
        self.runtime = runtime
        self.componentHost = componentHost
        self.coordinator = coordinator
        self.probe = probe
        componentHost.buildLifecycle = coordinator
        componentHost.shouldUpdate = { [weak self] in self?.isClosed == false }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { size },
            invalidateHandler: { [weak componentHost] in componentHost?.reload() }
        )
        .withEnvironmentValue(\.asyncImageService, service)
        componentHost.setComponents { [weak self] in
            guard self?.isClosed == false else { return [] }
            return [makeViewComponent(content(), context: context)]
        }
    }

    var nodes: [ViewNode] { asyncImageLifecycleNodes(runtime.root) }

    func reload() {
        guard !isClosed else { return }
        componentHost.reload()
    }

    func render() {
        guard !isClosed else { return }
        _ = runtime.renderScene()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        probe.onConstruct = nil
        runtime.stopRenderLifecycleCallbacks()
        coordinator.close()
        componentHost.onReloadCompleted = nil
        componentHost.setComponents { [] }
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private struct AsyncImageLifecycleConstructionLeaf: View {
    typealias Body = Never
    let probe: AsyncImageLifecycleMountedProbe

    var body: Never { fatalError("The fixture supplies its retained component directly") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            probe.onConstruct?()
            return ViewNode(frame: Rect(x: 0, y: 0, width: 12, height: 8))
        }
    }
}

@MainActor
private final class AsyncImageLifecycleWindowHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let renderer: FakeRenderBackend
    private var isClosed = false

    init<Content: View>(_ content: Content) {
        let renderer = FakeRenderBackend()
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 300, height: 200), scaleFactor: 1)
        let window = Win32Window(title: "AsyncImage observation fixture", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "AsyncImage observation fixture", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window, renderer: renderer, batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.host = host
        self.window = window
        self.renderer = renderer
        host.windowDidCreate(window)
        host.resetObservabilityCounters()
    }

    var nodes: [ViewNode] { asyncImageLifecycleNodes(host.hostedRuntime.root) }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        host.onReloadContentCompleted = nil
        host.onObservedObjectReloadTaskCompleted = nil
        host.windowWillClose(window)
    }
}

@MainActor
private func asyncImageLifecycleNodes(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap { asyncImageLifecycleNodes($0) }
}
