All files in this directory are **SYNTHETIC TEST FIXTURES**. They are hand-written
examples of a public compiler source profile, not Apple compiler captures, SDK
observations, or SwiftUI compatibility evidence. `/SYNTHETIC/` paths do not name
files the tests should open. The tests copy only the wrapped raw diagnostic
strings and trace objects into their own output directory.

`synthetic-cases.json` preserves the profile's diagnostic spelling and trace
field types. Its `diagnostics` strings are fragments; the test normally prefixes
them with the fixture's `searchPathDump` to form a complete synthetic stderr
stream. The test script mutates those examples to exercise failed launches,
uncertain process closure, prebinding remarks, missing module loads, unknown
formats, invalid JSON, and mismatched evidence. No process record in this fixture
was produced by a compiler. Source flags and spellings are anchored to public
Swift commit
[`aa782beb23b8bd83bd16fca831532a05dd6cea39`](https://github.com/swiftlang/swift/tree/aa782beb23b8bd83bd16fca831532a05dd6cea39):

- [`DiagnosticsSema.def`](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/include/swift/AST/DiagnosticsSema.def#L1286)
  declares `cross_import_added` and `module_loaded`.
- [`SearchPathOptions.cpp`](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/lib/AST/SearchPathOptions.cpp#L107)
  defines the raw four-section search-path dump. Module-loading diagnostics also
  include required, optional, and ignored transitive-dependency remarks; those
  are retained separately from module loads.
- [`ImportResolution.cpp`](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/lib/Sema/ImportResolution.cpp#L1604)
  reports a cross import before the implicit import has been bound.
- [`ASTContext.cpp`](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/lib/AST/ASTContext.cpp#L2864)
  reports a returned module, including source and loaded file metadata.
- [`LoadedModuleTrace.cpp`](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/lib/Frontend/LoadedModuleTrace.cpp#L50)
  defines the version 2 schema. Later sections substitute interface paths and
  append compact JSON plus LF; the trace is not a complete compiler read log.
- [`module-trace.swift`](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/test/CrossImport/module-trace.swift#L6)
  records an implicit cross import as directly imported. That boolean does not
  prove the overlay was lexically imported by the probe.
- [`swift_symbolgraph_extract_main.cpp`](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/lib/DriverTool/swift_symbolgraph_extract_main.cpp#L46)
  accepts its own option class, so frontend tracing flags are not extractor flags.

The source profile has not been qualified against the pinned Apple 6.3.3 binary.
Unknown diagnostic or trace formats remain incomplete evidence. An observed
module load does not establish which `.swiftoverlay` occurrence was selected,
whether both lexical imports were necessary, public API completeness, runtime
behavior, or release readiness.
