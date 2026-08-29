/// A facade may preserve its actor-only environment across deferred native
/// selection. The retained runtime does not know the facade's context type.
@MainActor
package protocol RetainedFileDialogInvocationScope: AnyObject {
    func withInvocation(_ body: @MainActor () -> Void)
}

package protocol RetainedFileDialogScopedConfiguration {
    var invocationScope: (any RetainedFileDialogInvocationScope)? { get set }
}

extension RetainedFileDialogScopedConfiguration {
    package func withInvocationScope(_ scope: any RetainedFileDialogInvocationScope) -> Self {
        var configuration = self
        configuration.invocationScope = scope
        return configuration
    }
}

extension RetainedFileExporterConfiguration: RetainedFileDialogScopedConfiguration {}
extension RetainedFileImporterConfiguration: RetainedFileDialogScopedConfiguration {}
extension RetainedFileImporterMultiConfiguration: RetainedFileDialogScopedConfiguration {}
extension RetainedFileMoverConfiguration: RetainedFileDialogScopedConfiguration {}
