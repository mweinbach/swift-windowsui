import SwiftWindowsCore
import SwiftWindowsPlatform
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Source regressions for the shared native invocation helper after the List
/// join. The fixture admits no native commands and retains no original build
/// context after deriving the two invocation contexts.
@MainActor
final class NativeListInvocationContextTests: XCTestCase {
    func testDeferredRowInvocationDropsConstructionOwnershipAndKeepsNativeProviders() async throws {
        try checkInvocationContext(kind: .row)
    }

    func testDescriptorInvocationDropsConstructionOwnershipAndKeepsNativeProviders() async throws {
        try checkInvocationContext(kind: .descriptor)
    }

    private func checkInvocationContext(kind: NativeListInvocationProbe.Kind) throws {
        for builder in [false, true] {
            let probe = NativeListInvocationProbe(kind: kind)
            let host = MountedLazyListTestHost(size: Size(width: 160, height: 60)) {
                NativeListInvocationRoot(probe: probe, builder: builder)
            }
            defer {
                host.close()
                probe.releaseContexts()
            }
            XCTAssertEqual(probe.factories, 0)
            if kind == .row { XCTAssertNil(probe.fileContext) }
            XCTAssertNotNil(host.layout())
            XCTAssertLessThan(probe.factories, 128)
            XCTAssertTrue(probe.hadInstalledOwner)
            XCTAssertTrue(probe.hadInstalledEpoch)
            XCTAssertEqual(probe.hadLazyAttribution, kind == .row)
            XCTAssertEqual(probe.hadDescriptorAttribution, kind == .descriptor)

            let fileContext = try XCTUnwrap(probe.fileContext)
            let alertContext = try XCTUnwrap(probe.alertContext)
            for context in [fileContext, alertContext] {
                XCTAssertNil(context.viewIdentity.installedOwner)
                XCTAssertNil(context.viewIdentity.installedEpoch)
                XCTAssertNil(context.viewIdentity.lazyList)
                XCTAssertNil(context.viewIdentity.descriptorComponent)
                XCTAssertNil(context.stateMountCoordinator)
                XCTAssertEqual(context.retainedViewIdentity, probe.identity)
                XCTAssertEqual(context.canvasSize, Size(width: 160, height: 60))
                XCTAssertTrue(context.nativeDialogSession === probe.session)
                XCTAssertNotNil(context.nativeDialogOwnerRequest)
            }

            XCTAssertEqual(probe.environmentReadsAfterFileCapture, 0)
            XCTAssertEqual(probe.environmentReads, 1, "Alert invocation intentionally snapshots the environment")
            probe.scheme = .light
            XCTAssertEqual(fileContext.environmentValues.colorScheme, .light)
            XCTAssertEqual(probe.environmentReads, 2, "File invocation reads the original provider when invoked")
            XCTAssertEqual(alertContext.environmentValues.colorScheme, .dark)
            XCTAssertEqual(probe.environmentReads, 2)

            var suppliedSessions: [NativeDialogSession?] = []
            fileContext.withNativeDialogOwner { suppliedSessions.append($0) }
            alertContext.withNativeDialogOwner { suppliedSessions.append($0) }
            XCTAssertEqual(probe.ownerRequests, 2)
            XCTAssertEqual(suppliedSessions.count, 2)
            XCTAssertTrue(suppliedSessions.allSatisfy { $0 === probe.session })
            XCTAssertFalse(probe.session.hasPendingRequests)

            // Sanitized invocation storage is not a construction receipt. Row
            // departure must still revoke the original physical attachment.
            let attachment = try host.rowRoot("native.join.row.0").captureLazyListAttachmentProof()
            try host.scroll(to: 4_000)
            XCTAssertFalse(attachment.isCurrent)
            XCTAssertNil(host.find("native.join.row.0"))
            XCTAssertNil(host.coordinator.latestInstallationError)
        }
    }
}

@MainActor
private final class NativeListInvocationProbe {
    enum Kind { case row, descriptor }

    let kind: Kind
    let session = NativeDialogSession(
        windowKey: NativeWindowKey(), commandSink: NativeListInvocationRejectingSink(),
        executor: NativeDialogExecutor { _, _ in .cancelled })
    var fileContext: ViewBuildContext?
    var alertContext: ViewBuildContext?
    var identity: RetainedViewIdentity?
    var hadInstalledOwner = false
    var hadInstalledEpoch = false
    var hadLazyAttribution = false
    var hadDescriptorAttribution = false
    var environmentReadsAfterFileCapture: Int?
    var environmentReads = 0
    var ownerRequests = 0
    var scheme = ColorScheme.dark
    var factories = 0

    init(kind: Kind) { self.kind = kind }

    func capture(_ kind: Kind) {
        guard kind == self.kind, fileContext == nil, let original = ViewBuildContextScope.current else { return }
        hadInstalledOwner = original.viewIdentity.installedOwner != nil
        hadInstalledEpoch = original.viewIdentity.installedEpoch != nil
        hadLazyAttribution = original.viewIdentity.lazyList != nil
        hadDescriptorAttribution = original.viewIdentity.descriptorComponent != nil
        identity = original.retainedViewIdentity

        // Reuse genuine construction attribution, but use explicit independent
        // providers so the probe itself does not capture an original context.
        let context = ViewBuildContext(
            viewIdentity: original.viewIdentity, stateMountCoordinator: original.stateMountCoordinator,
            nativeDialogSession: session,
            nativeDialogOwnerRequest: { [weak self] continuation in
                guard let self else { return }
                ownerRequests += 1
                continuation(session)
            },
            canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
            environmentValuesProvider: { [weak self] in
                var values = EnvironmentValues()
                self?.environmentReads += 1
                values.colorScheme = self?.scheme ?? .dark
                return values
            })
        fileContext = context.retainedFileDialogInvocationContext()
        environmentReadsAfterFileCapture = environmentReads
        alertContext = context.retainedAlertInvocationContext()
    }

    func makeRow(_ index: Int) -> some View {
        factories += 1
        return NativeListInvocationRow(index: index, probe: self)
    }

    func releaseContexts() {
        fileContext = nil
        alertContext = nil
    }
}

@MainActor
private struct NativeListInvocationRoot: View {
    let probe: NativeListInvocationProbe
    let builder: Bool

    var body: some View {
        let _ = probe.capture(.descriptor)
        if builder {
            List { ForEach(0..<10_000) { probe.makeRow($0) } }.listStyle(.plain)
        } else {
            List(0..<10_000, id: \.self) { probe.makeRow($0) }.listStyle(.plain)
        }
    }
}

@MainActor
private struct NativeListInvocationRow: View {
    let index: Int
    let probe: NativeListInvocationProbe

    var body: some View {
        let _ = index == 0 ? probe.capture(.row) : ()
        Text("Row \(index)").frame(height: 20).accessibilityIdentifier("native.join.row.\(index)")
    }
}

private struct NativeListInvocationRejectingSink: NativeWindowCommandSink {
    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        command.reject(.staleWindow)
        return .rejected(.staleWindow)
    }
}
