import SwiftWindowsUI

/// File operations have their own presenter lease. Keep the original actor-only
/// providers; those closures retain their captures until the configuration and
/// any pending operation retire, even after direct build receipts are removed.
@MainActor
final class FileDialogInvocationContext: RetainedFileDialogInvocationScope {
    private let context: ViewBuildContext

    init(_ context: ViewBuildContext) {
        self.context = context.retainedFileDialogInvocationContext()
    }

    func withInvocation(_ body: @MainActor () -> Void) {
        ViewBuildContextScope.withCurrent(context, body)
    }
}
