# TextEditor navigation and caret reveal

`TextEditor(text:selection:)` uses the existing public bindings, retained input
controller, and inherited undo manager. This is an editing slice; it does not
open or save files, track document dirtiness, or implement `DocumentGroup`.

## Keyboard policy

| Key | Retained behavior |
| --- | --- |
| Up / Down | Move to the adjacent rendered visual line, including soft wraps. Preserve the original visual X across short lines and direction changes. At the first or last line, leave the insertion point unchanged. |
| Shift + Up / Down | Extend from the selection anchor using the same preferred X. Crossing or returning to the anchor preserves its identity. |
| Home / End | Move to the logical start or end of the current visual fragment. In right-to-left text, those are not necessarily the left and right screen edges. |
| Ctrl + Home / End | Move to the beginning or end of the document. Shift extends from the current anchor. |
| Ctrl + Up / Down | Reserved without moving the editor or an enclosing scroll container; paragraph navigation is not implemented. |

Explicit application keyboard shortcuts retain precedence. Editor navigation
runs before generic scrolling, including its Shift variants. Ordinary
single-line `TextField` and `SecureField` paths remain separate.

A soft-wrap boundary has two visual positions at one character offset:
upstream is the preceding line end, and downstream is the following line start.
The controller retains this affinity separately from selection direction.
Compatible rebuilds preserve it and preferred X. Horizontal navigation, pointer
placement, edits, explicit replacement selections, and changed source or shaping
geometry reset preferred X. Height-only resizing and paint-only style changes
do not reset it.

## One layout for display and input

The package-internal `RetainedTextEditingLayout` records the exact visual
fragments, original source ranges, caret stops, and selection regions. Wrapping
measures complete shaped fragments instead of counting columns. Each visible
fragment paints as one label without further wrapping. Selection backgrounds,
IME underlines, and the caret overlay that text; none split and reshape it.
Pointer hits, native IME caret rectangles, and keyboard movement use this same
snapshot and the viewport's actual retained placement.

The layout preserves spaces, tabs, graphemes, LF, CR, CRLF, and trailing empty
lines without writing to the binding. Existing Ctrl+V behavior still converts
CRLF and CR to LF. UTF-16 native hit positions are mapped to legal Swift
`Character` boundaries; native bidi selection pieces remain separate when a
logical range is visually discontinuous. Baseline offsets use the same local
translation for text, decorations, pointer hits, and reported caret geometry.

While IME composition owns the candidate selection, the new visual navigation
keys and pointer placement do not move the model insertion point. Marked text
still uses the shared displayed layout and does not enter the text binding or
automatic undo history until accepted through the existing composition path.

## The editor owns its viewport

The public focusable editor node keeps its identity, tags, controller, and undo
ownership. Its one child is an inset vertical scroll viewport. Only real visible
fragments and decorations occupy the content; there is no hidden source label
to measure, paint, expose to accessibility, or use as a caret reference.

Keyboard movement, accepted edits/replay, relevant reconciliation, and viewport
size changes request minimal caret reveal after layout settles. Requests check
the current controller, focus, runtime attachment, exact viewport owner, and
layout validity. A stale callback cannot scroll a replacement editor. Reveal
changes only that editor's viewport and cancels only its motion; it never
searches for an ancestor `ScrollView`. An unrelated rebuild or color change does
not pull a manually scrolled editor back to an unchanged caret.

## Validation and limits

`RetainedTextEditingLayoutTests`, `TextEditorNavigationTests`, and
`TextEditorViewportRuntimeTests` cover the new geometry, public control path,
and owner-bounded reveal. Existing text input, reconciliation, selection-index,
composition, construction-lifetime, and undo suites remain regression gates.
Synthetic layout tests are distinct from the authored genuine DirectWrite
checks; neither should be reported as executed until the serial test run passes.

Some custom typography cannot currently supply exact native caret geometry,
including source-changing small-cap transforms and ambiguous tracked shaped
clusters. The GDI fallback and disabled native glyph shaping also lack this
geometry. Such snapshots remain drawable but explicitly report
`hasCompleteCaretGeometry == false`; geometry-dependent navigation, pointer
placement, caret, and selection decorations are unavailable. Native text never
receives invented pixel-font caret positions. Overwide indivisible graphemes and
out-of-bounds typographic offsets can still clip within the viewport.

Wheel/drag scrolling qualification, drag autoscroll, Page Up/Down and paragraph
navigation, full UIA text/selection patterns, arbitrary ancestor transforms,
large-document performance, and pinned native editing parity remain separate
work. This slice does not qualify a complete document/editor template or native
IME behavior. [TextInputUndo.md](TextInputUndo.md) records the existing history
and external-model-write limits.
