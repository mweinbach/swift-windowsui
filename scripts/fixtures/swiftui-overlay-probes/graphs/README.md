These are small synthetic symbol graphs, not SDK captures or compiler output.
The tests invoke the unchanged streaming graph reader and inventory writer in
process. They never launch Swift, SwiftPM, an extractor, or a native probe.

The owner-named fixture deliberately has `module.name = DeclaringA`, although
the test copies it to `_GraphOverlay@ForeignOwner.symbols.json`. Its two
occurrences of one existing precise identifier have different constraints and
relationships. The other partition repeats the same identifier and bystander
name. The non-underscored module adds a type alias occurrence. All bytes, aliases,
duplicate occurrences, unknown fields, and original graph headers must survive.

At pinned Swift commit `aa782beb23b8bd83bd16fca831532a05dd6cea39`,
`lib/SymbolGraphGen/SymbolGraph.cpp` derives a recognized overlay's serialized
module name and bystanders from its declaring context. `SymbolGraphGen.cpp`
constructs filenames independently from the physical module and extension owner;
the extension owner does not replace the serialized module header. Bystander
order and repetitions are not normalized here. The extractor can automatically
emit further overlay graphs. Files without independent attribution evidence
must be retained as unreviewed, not assigned to the requested overlay by name.

The empty graph tests the valid zero-symbol supplemental case. A separate test
keeps the baseline primary graph's existing empty-graph rejection intact. A
successful invocation with zero observed files creates an explicit unreviewed
observation; neither case establishes that a module has no public API.
