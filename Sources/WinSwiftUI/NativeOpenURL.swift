import Foundation
import SwiftWindowsPlatform

/// A built-in link has no public result to return. Its optional internal
/// observer distinguishes an actual synchronous handler result from the
/// native owner's eventual shell result; admission is neither result.
enum BuiltInOpenURLResult: Equatable, Sendable {
    case inline(OpenURLAction.Result)
    case opened
    case failed(NativeDialogFailure)
    case revoked
}

/// The public OpenURLAction remains synchronous. Only Link and HelpLink use
/// this route for the marked framework default and a native-capable executor.
/// A custom handler returning .systemAction is still just that handler's
/// result, exactly as it is through the public API.
@MainActor
func performBuiltInOpenURL(
    _ url: URL, action: OpenURLAction, context: ViewBuildContext,
    completion: (@MainActor (BuiltInOpenURLResult) -> Void)? = nil
) {
    guard action.isSystemAction, openURLShellExecutor.supportsNativeOwnerExecution,
        context.nativeDialogSession != nil || context.nativeDialogOwnerRequest != nil
    else {
        let result = action(url)
        completion?(.inline(result))
        return
    }
    guard nativeDialogCallerIsCurrent(context) else {
        completion?(.revoked)
        return
    }
    guard let target = shellTarget(for: url) else {
        completion?(.failed(.invalidShellTarget))
        return
    }

    // An early invocation waits for the host's owner binding instead of
    // falling back to ShellExecuteW on the actor. Resolve each intent once.
    var ownerResolved = false
    context.withNativeDialogOwner { session in
        guard !ownerResolved else { return }
        ownerResolved = true
        let invocationContext = context.withNativeDialogSession(session)
        guard nativeDialogCallerIsCurrent(invocationContext) else {
            completion?(.revoked)
            return
        }
        guard let session else {
            completion?(.failed(.ownerUnavailable))
            return
        }
        ViewBuildContextScope.withCurrent(invocationContext) {
            session.request(
                .openURL(operation: "open", target: target),
                isCurrent: { nativeDialogCallerIsCurrent(invocationContext) }
            ) { response in
                let result: BuiltInOpenURLResult
                switch response {
                case .openedURL: result = .opened
                case .failed(let failure): result = .failed(failure)
                case .revoked: result = .revoked
                default: result = .failed(.unexpectedResult)
                }
                // There is no retained-model mutation here. Removing the view
                // after admission cannot rewrite an actual shell reply. The
                // session itself still qualifies delivery against owner loss.
                completion?(result)
            }
        }
    }
}
