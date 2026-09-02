# Owned native scheduling fixture

`swift-windowsui-native-smoke` is a separate Windows executable for one bounded
qualification attempt. Its implementation has run in focused native attempts;
the latest saved attempt at `1aacbb2` passed 24 of 27 predicates and failed.
The fixture is not yet qualified.
It does not add an application mode, change `App.main`, or turn the previous
standalone dispatch scheduling result into host qualification.

The fixture uses the ordinary `WindowCoordinator`, `WinSwiftUIWindowHost`,
retained runtime, native command mailbox, UIA provider, and renderer factory.
The existing host factory supplies `pacingMemory: nil`, so no pacing settings
are loaded or saved. Its one 560 by 380 window contains an observed phase label
and a 64-row public `List`. It uses no Settings scene, AppStorage, SceneStorage,
dialog, URL, clipboard, global input, network, or desktop/window capture.
There are no accepted arguments or environment-controlled fixture modes.

## Fixed workload and observations

The mounted `.task` must begin, suspend twice, and resume twice. Each of its
three phases must produce a current retained revision with a real successful
hardware presentation receipt. The trace correlates preparation, native reply,
actor consumption, and host acceptance by request, renderer attachment, window,
lifetime, surface generation, retained revision, device generation, and frame
number. Native start/completion timestamps keep the receipt's own epoch; they
are never subtracted from the observer's uptime timestamps. A submitted frame
is not a display-completion or pixel-fidelity result. Unknown/software adapter
receipts do not satisfy the hardware predicate.

Exactly 64 ordinary owner commands each emit one distinct package-only probe
record through the existing ingress admission/sequence path. These records do
not synthesize keyboard, pointer, or other operating-system input. Actual replies
and accepted/delivered sequences must match; command admission is not a reply.
The real owner, exact observer, live lifetime, ordinal range, and duplicate mask
are checked before any provider query and again before emission. The mask and
published sequence advance only after real admission. No alternate mailbox or
executor is introduced.

Ordinal 31 makes a real direct C-vtable ControlType query on N. Its captured
surface/sequence must reach A, and that call must finish without another native
command or message being processed inside the span. A nested direct query must
preserve the actual `E_FAIL` and empty output. Trace checks require every known
actor callback to run off N; they do not equate MainActor with the entry thread
or require all actor callbacks to use one physical thread.

Automatic ingress turns remain limited to 32 records and native command turns
to 16. The owned fixture now includes setup to prepare a real backlog before
measurement; it does not hold or reorder measured continuations. If it does
not observe a full 32-record turn with remaining backlog and unrelated actor
progress before the following turn, fairness is unexercised. If all other
predicates succeed, the intended exit is 2 (inconclusive), not 0.

After phase 1, the existing presentation drain callback takes one passive actor
snapshot. An independent controller then waits once for three seconds and asks
for the second snapshot. Neither A nor N receives work from that wait. Both
snapshots must be settled, retained revision/generation/sequence must match,
actual native timer state must be absent, and the interval must contain no
native wake/work/message, animation, ingress, or frame activity. There is no
periodic window sampling or forced frame. Unrelated activity at the owned window
may make this attempt fail; it is not suppressed or retried.

## Full C-call lease and close

After phase 2, an owned C provider reference arms one publication gate for the
next ControlType call on that concrete provider. The C call takes its real
`ProviderCall` lease before the actor callback, then holds it after preparing
the result and before publishing out memory. The independent worker's actual
thread ID must match the gate claimant. An unexpected UIA client taking that
slot is a negative result, not permission to probe other clients or retry.

While the worker is held, A requests the ordinary close. The fixture requires
actual UIA revocation and N's existing attachment-quiescence guard to block
destruction, with no observed `WM_NCDESTROY`. Only then does the independent
controller record a release intention and call the C gate's open function.
Its actual HRESULT is recorded separately: released work may finish before
that result record, so log order is not mistaken for release order. The worker
must return the actual `UIA_E_ELEMENTNOTAVAILABLE` with empty output.

The close predicates separately require native renderer detach before
`WM_NCDESTROY`, return from native destruction, real close reply delivery,
actor consumption of teardown/close, the owner's successful operating-system
thread join, actor stop consumption, and coordinator return with zero. Preparing
a reply, posting quit, or scheduling an actor task proves none of those later
steps. A final old-lifetime command must receive exactly one real `ownerStopped`
rejection without another probe effect. The worker's completion semaphore only
observes C-helper return; it is not described as an OS-thread join. Releasing
the fixture's primary provider/gate holders does not claim that every retained
bridge object has already deallocated.

## Termination observation and join validation

`nativeThreadTerminated` is recorded by the existing independent join worker
after its actual `WaitForSingleObject` call succeeds on the original owner
thread handle. The record keeps the recorder's actual calling thread ID, names
the original owner in `auxiliary`, and carries that call's actual wait result
in `value`. It is not an event emitted by N before returning. Windows signals
the thread object when the thread terminates; `WAIT_OBJECT_0` is the successful
signaled-object result. The later `nativeThreadJoined` record still requires
successful exit-code retrieval and handle closure.
([Thread termination](https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-thread),
[WaitForSingleObject](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject).)

The validator therefore classifies only this termination observation outside
the N-produced event list. A present termination record must be unique, have
wait result zero, name the unique original N, and share both that target and
its real observer thread ID with the unique successful join record. Owner
entry and successful close-reply return must precede termination, which must
precede join. All other N-produced records must still belong to N and precede
both termination and join. Duplicate receipts are counted before checking
success, so an extra failed join cannot hide beside a successful one.

Actor separation retains its original owner-entry-through-join interval,
including the gap between termination observation and join. An actor callback
on N in that gap is still rejected. After join, numeric thread IDs may be
reused; neither a later actor callback nor the observer must have a numerically
different ID from the retired N. Missing termination can preserve the existing
partial separation observation but can never prove a full join. Malformed or
duplicate termination fails both separation and full-join checks. Actor stop,
coordinator return, all original exit-status checks, and the separate absence
of fixture/owner/join failures remain required.

This correction changes no predicate names, command counts, turn limits,
timeouts, scheduling routes, or recorder identity API. The native attempt at
`66e9a7d` remains failed at 24 of 27 predicates; no saved trace is reclassified.
The two fairness predicates remain separate, unexercised obligations. The
separate `NativeOwnedSmokeTerminationObserverTests` matrix uses only synthetic
scalar input and directly checks separation, full join, and failure predicates.
The original 22 validation methods and 58 assertions stay intact; only their
two termination-receipt scaffolds adopt the actual producer shape. The new
source tests and a freshly bound native attempt still require serial execution
after integration. Source review and formatting do not supply those results.

## Bounds and future invocation

The observer belongs to this one pump/host instance. It stores at most 4,096
fixed scalar records and 1 MiB of exact NDJSON; overflow/nonfinite receipt times
make it permanently invalid. There are no arbitrary payload strings, observer
callbacks, or global registries. Counters and latest-record slots have a fixed
size. The controller waits on record activity outside A/N; it does not post
native messages. The C gate owns two manual-reset events with finite waits.

The soft controller deadline is 42 seconds from entry. An independent 45-second
self-watchdog starts before fixture construction and the fixture never disarms
it. On timeout it calls `TerminateProcess(GetCurrentProcess(), 124)` without taking a
trace lock, invoking DLL teardown, or attempting output. That path may leave
no final artifacts and is always a failed attempt. Ordinary `ExitProcess` can
terminate the watchdog before DLL detachment; only the external retained-process
bound covers a hang in that final phase. That external bound is not implemented
by a second general harness in this patch.

After separate authority to compile, use the existing serial build entry:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui-native-smoke
```

Do not launch as part of a build/test command. A later approved run must bind the
actual combined source, generated binary, tool/runtime inputs, and a fresh owned
working directory. The direct child argv contains only that exact executable
path, with no arguments. The parent proposal is one retained child, 60 seconds
total (55 plus 5 for direct-child termination), with no retry or fallback.
An existing denied P9 sealing route is not used or recreated.

The child writes only `trace.jsonl` (1 MiB) and `result.json` (128 KiB) into that
fresh directory, refusing existing outputs. The parent captures bounded stdout,
stderr, actual process identity and natural exit, plus fixed output/source/binary
metadata. The result's intended exit is not the actual exit receipt. Qualification
requires all predicates **and actual natural exit 0**, without watchdog,
intervention, output overrun, or missing evidence. Early termination leaves any
unfinished operation's outcome unknown and is never reported as graceful.

## Source tests and remaining gates

The new source roster is 15 observation methods, 22 validation methods, and
8 C publication-gate methods: 45 async methods in three new files. Existing
test files are unchanged from this successor's cdd5fd2 foundation. The fixture
originates at f475f08 on af26; its 45 test oracles are preserved in this join.

`Win32NativeSmokeObservationTests` covers fixed encoding, counters, capacity,
snapshot copies and invalidity. `NativeOwnedSmokeValidationTests` uses synthetic
scalar rows to reject missing/duplicate identities, wrong threads, unreturned
commands, prepared-only close, wrong gate claimant, insufficient idle, and
unexercised fairness. Synthetic rows are not native evidence.
`UIAPublicationGateTests` uses the actual C provider helpers with independently
released gates, including nested calls and revocation; it does not create a
window. All new actor-isolated test methods are async. Their source inventories,
generated registrations and actual outcomes must be kept separate.

This fixture does not qualify COM apartment marshaling, every UIA pattern,
interactive input/focus/modal/dialog/URL behavior, DPI/device recovery, software
fallback, pixel output, display timing, multiwindow teardown, arbitrary authored
work, or long-running idle. Those remain separate gates even after a successful
bounded attempt. This successor retains the root compiler repairs through
cdd5fd2 by context. Any later root updates require a fresh context join;
whole-file replacement is not an integration plan.

## Passive message target diagnostic successor

The two existing native dispatch records now carry a receiver category in
`auxiliary`: 1 is a thread message with no HWND, 2 matches the owner's control
window, 3 matches a recorded handle in the owner's registered-window collection,
and 4 is a nonnil target with neither recorded association. Missing metadata in
older traces remains unclassified; it does not imply category 4. These values
identify an association, not a sender, timer producer, class, or additional
Windows ownership capability. No HWND or message payload is recorded.

The category is captured once before `TranslateMessage`, only when this owner
has a smoke observer. The return record reuses that scalar even if dispatch
clears the target handle. Both original message values and original flags
expressions remain in place; the return flags retain their existing evaluation
after dispatch. Classification reads existing native state without querying
Windows or retaining a window across dispatch. It does not classify nested
sent messages that the existing outer message loop does not observe.

All 27 predicates, including the strict absence of every native dispatch during
idle, remain unchanged. There is no exception for a category or message number.
The 64-command workload, ordinal-31 query, native/actor turn budgets, original
time limits and trace caps are unchanged. The seven additional source tests
cover the pure category mapper, wire fields, omitted legacy metadata, and the
unchanged complete predicate dictionaries for positive and negative synthetic
traces. They do not create a native window or qualify quietness or fairness.

The optional field already exists in the trace ABI, but the controller's output
contract also pins the exact `Win32NativeSmokeObservation.swift` source bytes.
Adding the category declaration requires a reviewed successor of that source
pin; it is not compatible with an unchanged literal source-pin contract. The
other output-contract fields and checks need no relaxation. The diagnostic
source tests, original native94 cohort plus seven new methods, compilation and
any later native attempt require separate serial execution and fresh binding.
No saved native result is changed by this source addition.

## Passive GUI thread snapshot

When the existing observer publishes a zero timer-state value for a created,
live, nonquiescing window with its recorded handle, the native owner takes one
`GetGUIThreadInfo` snapshot using its explicit nonzero current thread ID. It
does not query the foreground thread or another window. The original record,
timer-state cache and flags are preserved. No new record or native action is
introduced; the snapshot supplies only the existing optional auxiliary field.

An absent field means unsampled; zero means the API call failed. A successful
value sets bit 7, uses bits 5-6 for no caret / recorded-window caret / other
caret (0/1/2), and preserves the five documented GUI flags in bits 0-4. No HWND,
caret rectangle or thread identifier is copied into this scalar. In particular,
`GUI_CARETBLINKING` describes current caret visibility, not proof of an active
timer or the source of a message. See Microsoft's [GUI thread information](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getguithreadinfo)
and [flag definitions](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-guithreadinfo).

The observation is a qualified instantaneous sample, not continuous coverage
of the later idle interval. It cannot establish who sent message `0x118` or why.
Seven new pure encoding tests supplement the existing 101-method focused
cohort; fresh compilation and execution remain required. All 27 predicates,
64 commands, ordinal-31 query, turn budgets, deadlines and trace caps remain
unchanged. A later native attempt also needs a fresh executable binding.

## Passive foreground activation result

The first existing `SetForegroundWindow` return in this fixture is recorded as
the appended `nativeForegroundActivationResult` event (85). Its `value` is 1
when the call brought the window to the foreground and 0 when it did not.
No event means unrecorded; zero is a recorded outcome, not a native error code.
Window identity and the current copied surface generation/native sequence name
the source context after the API returns. The normal recorder supplies its
timestamp and executing thread ID. No extra Win32 query or HWND is recorded.

The observation object reserves one attempt for the entire fixture before
calling the unchanged recorder, including when its fixed capacity or invalidity
state rejects that attempt. Later activation results do not replace it. Normal
applications have no observer and perform no diagnostic call. The activation
call, its return value, window/input behavior and all timer policies stay intact.

Windows documents a taskbar-flashing fallback for restricted foreground
activation, but this scalar cannot identify a message producer or prove that
flashing occurred. A successful result also does not prove continued foreground
status. See [SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow).
The diagnostic never qualifies idle, exempts `0x118`, or supplies fairness
evidence. All 27 predicates, workload, deadlines, turn limits and trace caps
remain unchanged.

Eight new recorder/vocabulary/parser source tests supplement the existing
tests without changing them. They are not native observations and remain
unexecuted at this private source handoff. Appending the event and recorder
method changes the observation source pin: an output-contract successor must
pin the exact reviewed file and retain the earlier 0...84 event encodings.
Any later compilation, test run, binding or native attempt remains a separate
root-owned decision.


## Backlog preparation for the owned fixture

Only the native smoke session installs `Win32NativeSmokeIngressSetup` on its
fresh facade, before native HWND creation and only with its smoke observer.
Normal hosts keep the original ingress initializer. Setup remains dormant
during startup, so ordinary ingress delivery continues. Arming follows provider
acquisition and precedes the original 64 submissions.
Each original request ID is registered before submission. Only its actual
successful reply supplies a readiness receipt; the existing reply mask still
records both successful and failed replies.

Preparation parks at most one original automatic ingress operation. The direct
C query at ordinal 31 still performs its real synchronous prefix flush. The
remaining ordinals 31 through 63 must all produce distinct successful receipts
for the original window lifetime and ordered native sequences. Selection also
requires the original first-release request and all 64 registrations. It adds
no native command, probe, timer, sleep, polling, or replacement workload.

On the actor, the selected candidate task forwards the original release
request and then checks the current facade, original ingress, window/surface
keys, close lifetime, lifecycle flags, and copied queue state. Preparation
requires at least 33 queued records, accepted sequence through the suffix, no
committed suffix record, an existing scheduled turn, and no in-flight or
terminal failure. An intervening legitimate flush aborts setup without refill
or rearm. The helper permanently opens and invokes the original operation in
the same actor segment. Measured continuations retain their original one-Task
scheduling, 32-record limit, token ownership, and observations.

Successfully resuming the parked continuation makes the model runnable;
invoking the release relay alone proves neither successful resumption nor model
progress. Only the actual resumed trace record proves progress. The 33 new
async `Win32NativeSmokeIngressSetupTests` use the real in-memory ingress and a
manual actor driver, not an HWND or native query.
They include both possible actor choices: selecting the ingress successor
before the runnable model leaves the original fairness predicate false. The
new source tests remain unexecuted at integration; actual results belong to
separately recorded source-bound runs.

Abort and teardown preserve ownership of the original operation for one
invocation on A and attempt an existing pending release at most once. Missing
weak model or invalid current binding prevents preparation. These paths assume
the queued actor work executes; they do not promise completion after a hard
exit or a stopped executor. Idle readiness additionally requires no held or
selected setup work or unforwarded release; the existing host snapshot still
checks the actual
ingress queue and reservation. All 27 predicates, original work/query order,
trace limits, three-second idle interval and internal/external deadlines remain
unchanged. The earlier 24/27 result is not reclassified by this preparation.


## Recorded native run at f64b73a (2026-09-02)

A fresh source-bound run at `f64b73a3055b56cf95734551c7be93057fa25aac`
passed all 27 unchanged predicates and exited naturally with child/controller
code 0 after 11.266 seconds. Its trace has 1,701 records, 416,978 bytes,
SHA-256 `230def74dae2f89de0f651af976faf9bdd83cac34952da3624df28ae46d14f04`.
The retained local run is
`artifacts/goal-ninth-native-owned-smoke-9f99c6d83e384844b1c4225291665250`.
The earlier 24/27 attempt remains a separate failed result.

This run exercised the actual 32-record backlogged turn and a following turn,
with the model's real first resumption between them. The idle boundary records
are consecutive and 3.0013587 seconds apart; the settled snapshots match.
The original 64 probes/replies, native close/join sequence, and three phase
frame-submission checks passed. No diagnostic pause, forced shutdown, timer
exception, increased bound, or replacement workload was used.

Before launch, the same clean source passed 23 logical-geometry tests, all 33
ingress-setup tests, eight activation tests and the 116 native prerequisites.
A separate 76-case publication/lifetime cohort also passed. The warmup's actual
native executable link and stable PE hash are retained separately from the
incremental 116-case run, which did not relink that executable. A new single-use
binding joined those inputs. Source/index and pinned input endpoints matched;
a separate process census after closure was empty.

These results qualify this fixed local smoke attempt only. Direct C-vtable
calls do not qualify COM routing or assistive-technology applications, frame
submission does not prove display completion, and runtime DLL file pins do not
prove loader selection. This is not hardware pacing, macOS parity, full-suite,
or clean-machine release qualification.
