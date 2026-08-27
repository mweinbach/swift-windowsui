# Single-file FileDocument export

The SwiftUI-shaped `fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)`
overload now serializes a nonnil `FileDocument` and writes its regular-file
contents to the accepted file URL. Selecting a destination alone is no longer
reported as successful export. This implements one part of the full
compatibility goal; it does not complete document architecture or reduce that
goal's requirements.

`WinSwiftUI/FileDocumentExport.swift` calls the document's
`fileWrapper(configuration:)` and exposes its regular-file bytes through the
renderer-neutral `RetainedFileExporterConfiguration.dataProvider`. The
retained layer imports no WinSwiftUI document or wrapper type.
`SwiftWindowsUI/FileExport.swift` validates the destination, obtains all
serialized bytes, and calls `Data.write(to:options: .atomic)`.
`ComponentHost` delivers success only after that call returns.

Foundation's atomic-save option writes an auxiliary file before replacing the
destination. Encoding errors therefore occur before any destination write,
and write errors propagate instead of becoming URL-selection success. This
uses Foundation's existing contract; it does not promise hardware or
power-loss durability, or stronger guarantees than the selected filesystem
and Foundation implementation provide. See the [atomic option](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic)
and the [Swift 6.3 Windows implementation](https://github.com/swiftlang/swift-foundation/blob/swift-6.3-RELEASE/Sources/FoundationEssentials/Data/Data%2BWriting.swift).

The exporter uses the requested content type when it is in
`Document.writableContentTypes`, otherwise the first writable type. The
default writable list is the readable list, and document implementations may
override it. An empty writable list fails explicitly. A nil document does
not present a dialog. Dismissing the save dialog resets `isPresented` without
serializing, writing, or calling `onCompletion`. For a completed attempt,
presentation is reset before the success or failure callback. These rules
follow Apple's [single-document exporter contract](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)).

This standalone export does not maintain a document-session file wrapper, so
the write configuration supplies `existingFile: nil`. An unrelated file
already at the chosen destination is not substituted for the document's
current content. See [existingFile](https://developer.apple.com/documentation/swiftui/filedocumentwriteconfiguration/existingfile).

The most recently reconciled presenter is selected when a dialog begins.
That operation keeps its document value and completion through presentation
reset and any resulting view rebuild. Reentrant requests are processed after
the active operation and callback finish, so a completion can request a
subsequent export. This is the retained runtime's policy; native behavior for
document mutations while the modal panel is open has not been qualified.
Successful export also does not mark a subsequently edited document clean.

Directory/package wrappers, wrappers without regular-file data, mixed
directory/data wrappers, multiple documents, `ReferenceFileDocument`, and
`Transferable` export remain unsupported. They must not report successful
writes. The legacy `Any` overload remains available for source compatibility
but cannot supply a FileDocument serializer; unsupported inputs fail.
Regular-file wrapper names do not redirect the accepted destination.

Serialization and writing currently run synchronously on the main actor.
Apple's `FileDocument` contract instead requires thread-safe/Sendable
conformers and serialization outside the main actor. That scheduling and
ownership work remains open, as do document-session wrapper reuse, directory
packages, multi-file export, and complete native behavior qualification.
The existing protocol shim's custom associated configuration types are not
supported by this typed exporter; Apple's `WriteConfiguration` is a fixed
typealias. No DocumentGroup, close, dirty-state, Save As session, undo, or
external-change coordination behavior is established by this implementation.
See Apple's [serialization requirements](https://developer.apple.com/documentation/swiftui/filedocument/filewrapper(configuration:)).

`FileDocumentExportTests` exercises real round trips and replacements,
unchanged original bytes after encoding/read-only-destination failures,
directory-destination failure, empty-file export, cancellation, content-type
selection, nil documents, reconciliation, and chained dialogs.
`FileDialogIntegrationTests` also verifies written bytes and dialog filters.
Every filesystem destination returned by an exporter mock is inside a fresh UUID directory under OS
temp, with cleanup restricted to that owned directory. The tests use no
hardcoded user or example save paths.
