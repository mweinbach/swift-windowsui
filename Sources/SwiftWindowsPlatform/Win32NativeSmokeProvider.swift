import CUIAInterop
import SwiftWindowsCore
import WinSDK

/// One retained, concrete C provider from the fixture's real native attachment.
/// Its C implementation owns atomic references and full-call context leases;
/// this value never contains a Swift UI object or a borrowed actor pointer.
/// Calls are direct-vtable evidence, not evidence of COM apartment routing.
package final class Win32NativeSmokeProvider: Sendable {
    private let address: UInt

    fileprivate init(adopting provider: UnsafeMutableRawPointer) {
        address = UInt(bitPattern: provider)
    }

    private var provider: UnsafeMutableRawPointer { UnsafeMutableRawPointer(bitPattern: address)! }

    deinit { SWU_UIAReleaseProvider(provider) }

    package func controlType() -> Win32NativeSmokeControlTypeResult {
        let startedAt = PlatformClock.now()
        let threadID = GetCurrentThreadId()
        var value: Int32 = 0
        let status = SWU_UIAProviderGetControlTypeResult(provider, &value)
        return Win32NativeSmokeControlTypeResult(
            status: status, value: value, threadID: threadID,
            startedAt: startedAt, completedAt: PlatformClock.now())
    }

    package func armPublicationGate() throws -> Win32NativeSmokePublicationGate {
        var gate: OpaquePointer?
        let status = SWU_UIAProviderArmControlTypePublicationGate(provider, 30_000, &gate)
        guard status >= 0, let gate else {
            throw NativeWindowOwnerFailure.native(operation: "ArmControlTypePublicationGate", code: Int64(status))
        }
        return Win32NativeSmokePublicationGate(adopting: gate)
    }
}

package struct Win32NativeSmokeControlTypeResult: Equatable, Sendable {
    package let status: Int32
    package let value: Int32
    package let threadID: UInt32
    package let startedAt: Double
    package let completedAt: Double
}

/// The C gate owns both events and is independently reference counted. This
/// single controller reference may be used by the fixture's external worker;
/// no UI actor or native-owner acknowledgement is needed to open the gate.
package final class Win32NativeSmokePublicationGate: Sendable {
    private let address: UInt

    fileprivate init(adopting gate: OpaquePointer) { address = UInt(bitPattern: gate) }

    private var gate: OpaquePointer { OpaquePointer(bitPattern: address)! }

    deinit { SWU_UIAReleasePublicationGate(gate) }

    package func waitUntilEntered() -> Int32 {
        SWU_UIAPublicationGateWaitUntilEntered(gate, 30_000)
    }

    package var enteredThreadID: UInt32 { SWU_UIAPublicationGateEnteredThreadID(gate) }

    package func open() -> Int32 { SWU_UIAPublicationGateOpen(gate) }
}

/// Executes only after ordinary mailbox admission, against the actual owner
/// context and installed UIA attachment. No native command reports an effect
/// from admission alone; rejection completes its real one-shot reply.
package struct Win32NativeSmokeAcquireProviderCommand: NativeWindowOwnerCommand {
    package let windowKey: NativeWindowKey
    package let requestID: NativeWindowRequestID
    private let attachmentID: NativeWindowAttachmentID
    private let reply: NativeWindowReply<Win32NativeSmokeProvider>

    package init(
        windowKey: NativeWindowKey, attachmentID: NativeWindowAttachmentID,
        requestID: NativeWindowRequestID = NativeWindowRequestID(),
        reply: NativeWindowReply<Win32NativeSmokeProvider>
    ) {
        self.windowKey = windowKey
        self.attachmentID = attachmentID
        self.requestID = requestID
        self.reply = reply
    }

    package var commandReply: NativeWindowCommandReply { reply.commandReply }

    package func execute(in context: any NativeWindowOwnerContext) throws {
        guard context.surface.key == windowKey else { throw NativeWindowOwnerFailure.staleWindow }
        guard let attachment = context.attachment(for: attachmentID) as? UIANativeProviderAttachment else {
            throw NativeWindowOwnerFailure.missingAttachment(attachmentID)
        }
        guard let provider = attachment.retainedRootProviderForTesting() else {
            throw NativeWindowOwnerFailure.unavailable
        }
        reply.complete(.success(Win32NativeSmokeProvider(adopting: provider)))
    }

    package func reject(_ failure: NativeWindowOwnerFailure) { reply.complete(.failure(failure)) }
}
