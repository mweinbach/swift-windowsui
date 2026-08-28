# Retained text undo and redo

Ordinary nonsecure `TextField` and `TextEditor` controls register accepted text edits
with their inherited `EnvironmentValues.undoManager`. Hosted windows supply a
stable default manager; an environment override can share a manager or set it
to `nil` to disable automatic history. `SecureField` does not create an
automatic history session or store plaintext undo payloads.

Each accepted text change is one action, named `Edit Text`. Typing, deletion,
selection replacement, paste, cut, and an accepted IME result use the same
registration path. Caret movement, selection changes, IME preedit updates, and
composition cancellation do not register actions. An active composition blocks
replay until its end or cancellation, including the interval between a native
result and the end-composition event. Undo and redo do not use the clipboard,
accessibility values, or logging to transfer their text payloads.

An action stores a replacement delta at grapheme offsets and the before/after
caret, selection, and affinity. Its retained editor session stores one current
text checkpoint. This avoids retaining a whole document copy for every ordinary
keystroke, although computing and applying deltas still examines the text and
is not a long-document performance guarantee. There is no automatic typing,
event-loop, or explicit-group coalescing in this implementation.

## Bindings and retained identity

History follows the retained control, not a temporary view value or a closure
from its first build. After reconciliation, replay uses the current text and
selection bindings. A binding setter can synchronously rebuild or remove the
control; generation checks prevent the interrupted edit from adding a stale
inverse. A selection explicitly changed by application code during a text
setter takes precedence over the saved selection.

History cleanup and binding getters can also run application callbacks before
the write starts. If those callbacks detach or replace the editing controller,
the interrupted edit is cancelled without writing through the old binding.
Its pending undo ticket is cancelled too, leaving subsequent input and existing
history usable. Input is not retried against a different configuration using
the interrupted edit's selection offsets.

Programmatic binding changes do not automatically register text undo. A text
replacement different from the session checkpoint clears that editor's history
when it is observed during reconciliation, the next edit, or replay preflight.
An accepted edit that happens while registration is disabled also clears that
editor's older history. Rejected or normalized binding writes are handled
conservatively: they do not register the proposed value, and stale history for
that editor is removed rather than replaying a value the binding did not accept.
Applications that need formatter-aware model undo can register model actions
explicitly.

Arbitrary `Binding` closures do not expose a document identity. Rebinding the
same retained control to a different document containing equal text cannot be
detected. A document switch must change the editor identity, for example:

```swift
TextEditor(text: $document.text)
    .id(documentSessionID)
```

The identifier must represent the document session, not the current text or
selection. Changing that identifier, removing the control, changing between
secure and nonsecure input, or replacing its manager ends its old history.
Equal-text replacements with an unchanged identity are not a new session.

## Session-owned document bindings

The internal [document session stage](DocumentSessions.md) supplies an explicit
binding source and accepted-edit ticket for its writable configuration. Those
bindings use the session's model inverses instead of the ordinary editor delta
path. Direct document assignments and editor edits therefore share one undo
authority. A model assignment accepted through a computed projection remains
an action even when the projected text is unchanged. A retired managed source
does not become an ordinary binding with fresh local history.

An editor may attach selection to its exact accepted model-action receipt.
It cannot attach to a later direct assignment by inspecting the stack top.
Losing the editor removes optional selection behavior, not an accepted model
inverse. Generated key-path projections carry location identity; arbitrary
closure, optional, and collection projections do not invent equivalent
selection identities. Replay preparation reads a cached observation without
calling an application selection getter after the model action is consumed.

After model replay, selection restoration settles input eligibility before
reading bindings. The final checks do not run layout again. A checked runtime
stamp advances on invalidation and every resolved-layout entry, including a
nested pass draining a callback queued before the restore. Any observed pass
after capture, changed explicit selection, or exhausted stamp refuses that
optional restore. This is a conservative rule for observable mutations and
layout, not detection of every silent custom-binding side effect.

This managed path keeps its session manager even under an editor subtree
override; nil session history does not enable a second local manager. Active
composition blocks model replay. Managed secure input is unsupported and
rejects edits, because a whole-model inverse could otherwise retain plaintext.
Ordinary `SecureField` behavior is unchanged. These rules do not qualify native
document-manager overrides, Foundation typing groups, or reference-shaped
model snapshots. Default native DocumentGroup activation remains disabled.

Boolean and item-based sheets keep a stable retained host around their base
content, including while unpresented. Opening or dismissing a sheet therefore
preserves the background editor's identity, selection, caret, and history;
the active modal scope still blocks replay into that background editor.

## Commands and lifecycle

While an eligible nonsecure editor is focused, exact Ctrl+Z requests undo and
exact Ctrl+Shift+Z or Ctrl+Y requests redo. Existing explicit command handlers
and shortcut routing retain precedence. This fallback handles text-editor
targets in the originating runtime; it does not replay an unrelated manual
application action or an action owned by another window. An application can
still call its manager explicitly for application commands.

Replay checks the current editor configuration before popping the action.
Disabled, detached, hidden, or modal-blocked editors cannot replay, and an
ineligible top action is not skipped to execute a different action underneath.
Reentrant requests do not consume another action. The manager's `canUndo` and
`canRedo` still report recorded history; they do not perform all editor input
eligibility checks or provide native menu validation.

Closing a host marks every current editor session invalid, then revokes all
mounted State writes before releasing State or history payloads. A State value's
deinitializer cannot replay a closing plain-binding editor, and discarded undo
payloads cannot write through an escaped mounted State binding. History cleanup
removes only the closing sessions' actions. Render lifecycle delivery stops
before cleanup, and tasks are cancelled after State and editor writes are
revoked; a synchronous cancellation handler cannot regain either capability.
The host still
delivers normal focus-exit callbacks before detaching the controllers. This
also applies when a sheet editor is focused. A refused close keeps history.
Neither an overridden manager nor a default manager deliberately shared with
another window is cleared wholesale: other windows' editor actions and manual
application targets remain owned by their callers.

Ordinary reconciliation identifies all departing editors before any branch
starts dismantling or disappearance callbacks. This follows the State epoch's
ownership preparation and leaves compatible surviving sessions untouched. A
change of undo manager or incompatible input kind retires the old session even
when its retained node survives. A
callback in an earlier branch therefore cannot replay another editor departing
later in the same adoption. Direct retained removals and GeometryReader adoption
use the same ownership boundary.

If a host is released without explicit window-close notification, its isolated
deinitializer revokes editor and State ownership and purges those editor targets.
An externally retained runtime or binding does not extend the host's write
permission. This fallback does not invoke native window teardown or explicit
focus, disappearance, or window-closed callbacks. Explicit close retains the
existing pointer, focus, and window-closed callbacks. Neither path adds
whole-tree `onDisappear` delivery for window closure.

## Validation and remaining scope

`TextInputUndoTests` exercises public controls through `WinSwiftUIWindowHost`,
including repeated keyboard and direct replay, selection, Unicode, IME,
clipboard operations, environment overrides, modal input isolation, identity
changes, external replacements, setter reentry, removal, and window closure.
`TextInputUndoSessionTests` covers replacement deltas and manager/session races;
`UndoManagerTests` protects ordinary application targets and reciprocal action
registration. `EditorStateOwnershipTeardownTests` covers the combined mounted
State/editor ownership boundaries, including payload deinitializers and escaped
handles. Run these with the existing text input, reconciliation, and close suites
when changing the integration.

This is a bounded editor history path, not a complete document workflow. The
separate internal document stage adds model history and saved checkpoints,
with explicitly injected headless scene hosting. Native activation and final
unsaved-close integration remain blocked. Native typing-group behavior, full
Foundation grouping/event notifications, platform Edit-menu validation,
native IME/selection parity, full editor scrolling, and autosave remain open.
Same-source API compatibility
does not establish those behaviors without a pinned native reference.
The bounded visual-line navigation and editor-owned keyboard caret reveal are
documented separately in [TextEditorNavigation.md](TextEditorNavigation.md).
