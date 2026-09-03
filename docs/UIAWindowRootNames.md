# Window root names in UI Automation

The retained Windows host supplies its created window's title as a fallback
Name for an otherwise unnamed window root. This is copied host metadata in
`RuntimeUIAElementTreeSource`; it does not assign an accessibility label or
text to a retained node. A plain window root therefore keeps its PANE control
type, ID zero, child structure, geometry and existing capabilities.

The fallback applies only when the projected source is the ordinary physical
runtime root, its projected Name is empty, and it has no authored label, text,
explicit child behavior or selected-content role. An explicit empty label or
text remains empty. Explicit `.ignore`, `.combine` and `.contain` behavior
preserves the projection's own name, including an empty result. Selected
content projected as ID zero retains its selected node's name; it never borrows
the window caption. Descendant names are unchanged.

The source decides fallback eligibility from the fresh projection before
calling a legacy screen-bounds mapper. Only the copied string crosses that
callback. A callback changing authored metadata affects the next fresh query,
not the already captured name in the current query. Hidden roots and released
runtimes still produce no snapshots.

Both legacy and native-owner host wiring copy `Win32Window.title`. The title
is immutable in the current host contract; this does not add a dynamic title
subscription. Raw sources constructed without a window name keep their prior
behavior. No app-facing API or platform-specific modifier is required.

A window Name is not text-document content. This fallback does not enable
Text/Text2, held-document reads, Value or other control patterns and cannot
replace the original provider, session, surface, request or ownership checks.
Native name delivery and shutdown still require their existing integration
tests; a passing headless snapshot test alone does not qualify COM or Narrator.

`UIAWindowRootNameTests` covers headless host wiring, metadata preservation,
explicit and selected names, callback reentrancy, weak ownership and absence
of new Text or pattern authority. Existing source, projection, selected-content,
request and provider-lifetime tests remain separate regression coverage.

All eleven new naming tests and twenty-two existing related controls passed
in the combined 360-method run at `7d1ffdf`. The
[aggregate](../artifacts/lookup-window-image360-7d1ffdf-results.json) records
exact starts and terminals and clean owned-process closure. This qualifies
the selected headless behavior, not native caption delivery or Narrator.
