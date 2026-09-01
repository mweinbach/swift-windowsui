import SwiftWindowsCore

/// The fixed fixture submits exactly ordinals 0...63 through the ordinary
/// mailbox. Only ordinal 31 also performs the real synchronous C provider
/// query; all replies retain the existing Core arbitration capability.
package struct Win32NativeSmokeCommand: NativeWindowOwnerCommand {
    package let windowKey: NativeWindowKey
    package let requestID: NativeWindowRequestID
    private let ordinal: UInt32
    private let provider: Win32NativeSmokeProvider
    private let observation: Win32NativeSmokeObservation
    private let reply: NativeWindowReply<NativeWindowSurface>

    package init(
        windowKey: NativeWindowKey, requestID: NativeWindowRequestID,
        ordinal: UInt32, provider: Win32NativeSmokeProvider,
        observation: Win32NativeSmokeObservation,
        reply: NativeWindowReply<NativeWindowSurface>
    ) {
        self.windowKey = windowKey
        self.requestID = requestID
        self.ordinal = ordinal
        self.provider = provider
        self.observation = observation
        self.reply = reply
    }

    package var commandReply: NativeWindowCommandReply { reply.commandReply }

    package func execute(in context: any NativeWindowOwnerContext) throws {
        try validateNativeSmokeProbe(in: context, observation: observation, ordinal: ordinal)
        guard context.surface.key == windowKey else { throw NativeWindowOwnerFailure.staleWindow }
        if ordinal == 31 {
            let captured = context.surface
            observation.record(
                .nativeQueryStarted, windowKey: windowKey, requestID: requestID, generation: captured.generation,
                nativeSequence: captured.geometry.nativeSequence, value: Int64(ordinal))
            let result = provider.controlType()
            observation.record(
                .nativeQueryCompleted, windowKey: windowKey, requestID: requestID,
                generation: captured.generation, nativeSequence: captured.geometry.nativeSequence,
                value: Int64(result.status), auxiliary: UInt64(UInt32(bitPattern: result.value)))
            guard result.status >= 0 else {
                throw NativeWindowOwnerFailure.native(operation: "NativeSmokeControlType", code: Int64(result.status))
            }
            guard result.value != 0 else {
                throw NativeWindowOwnerFailure.execution("Native smoke control-type query returned no value")
            }
        }
        let surface = try emitNativeSmokeProbe(
            in: context, observation: observation, requestID: requestID, ordinal: ordinal)
        reply.complete(.success(surface))
    }

    package func reject(_ failure: NativeWindowOwnerFailure) { reply.complete(.failure(failure)) }
}
