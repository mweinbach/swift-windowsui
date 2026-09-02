# Native display measurement

`NativeDisplayMeasurement` checks associations among supplied typed facts. It
checks identities, clock bases, lifecycle intervals, Start/Stop pairing,
multiplicity, source health and bounded coverage. A unique association means
unique **among the supplied facts**. It does not authenticate a capture, derive
input effects, count demanded display deadlines, choose a quantile population,
or return a hardware qualification. Its 77 tests passed on `bb755b5`; that is
evidence for the checker, not for a monitor or the acquisition code below.

The optional native application journal acquires a smaller set of actual
application observations. Pass `--native-display-journal C:\capture\run.json`
once to the native executable. The directory must already be writable and the
destination must not exist. Drive-qualified syntax does not certify the drive
or its parent directories as a physical local disk. No environment variable or benchmark label enables
it. Configuration is parsed once, before native startup; invalid configuration
prints a diagnostic and leaves ordinary startup and exit handling unchanged.
It neither opens another window nor starts a workload or a capture timer.

Only the primary host on the native presentation route receives the immutable
recorder. Secondary windows, custom synchronous/headless startup, and the
ordinary default with no argument do not sample or bind acquisition contexts.
The first supported renderer path is the native scene batch kernel. A backend
without the optional acquisition capability, or an invoked separate frame
renderer, leaves acquisition incomplete; neither changes renderer selection or
its existing fallback behavior.

The journal preserves the original request UUID, window/lifetime/attachment
IDs and surface generation. It records the prepared scene's QPC value and
content revision, native entry/completion, the existing Present call's two raw
QPC samples, sync interval, flags, HRESULT and issuing `BackendFrameID`, then
the real reply callback and later actor consumption. Actor delivery is not
complete until the existing user completion callback returns. A content
revision is not an input event or evidence that a particular input affected a
frame. Preparation occurs after scene construction; it is not the start of all
active framework work.

Command-entry bookkeeping records entry before native validation. The backend
recording scope begins only inside the attachment's existing execution gate,
after validation and construction. That scope clears before the gate opens,
the existing snapshot is consumed, or the reply callback executes. Rejected nested commands cannot
replace the outer context. A pre-render failure cannot inherit the previous
frame's submission. Core's original reply callback records transport rejection
even when Core bypasses `command.reject`; unsent local rejection is recorded
separately and never invented as a native receipt.

Swap-chain epochs contain copied identities, device generation and a scalar
address. A successful creation begins an epoch. Successful surface lease
changes explicitly end and begin a `surfaceChanged` epoch; they do not claim a
new COM allocation. Owner teardown ends the epoch after the existing owned
COM reference release returns, using a sample immediately before that release.
This does not prove when every external COM reference or display queue ended.
The epoch token survives independently of the last request. Failed detach
keeps the epoch open; partial attachment cleanup closes it only after the
corresponding actual release. No journal value retains a native window,
attachment, runtime, renderer or COM object.

The native source uses one checked, cached QPC frequency and integer timestamps
with PID/TID. Zero timestamp and frame components remain valid. Session UUIDs
are local journal identities, not boot or ETW clock-origin proof. Raw PID/TID
and addresses require original lifetime/rundown evidence before normalization
into the checker's process/thread/epoch facts. UInt64 fields are encoded as
decimal JSON strings to avoid loss through floating-point readers.

Hard limits are eight clock sources (this route uses one), 64 epochs, 8192
requests and 8192 replies, plus 32 MiB for the encoded document. The request
limit includes non-frame commands; it is not an 8192-frame promise. Arrays and
the request index reserve their finite capacity. Capacity overflow, rejected
requests, unavailable clocks, inconsistent identities, unfinished calls, open
resource epochs or pending actor callbacks prevent complete publication.
Identical-present skips and refusals before a request exists have separate
checked counters, not synthetic request IDs. These counters do not establish
the timing or demand of each omitted interval. The encoded ceiling is not a
total process-memory, ETW-buffer, disk-session or long-session resource bound.

There is no disk write, extra task, wait, polling, ETW session or writer callback
on the native recording path. Recording still has finite sampling and mutex
overhead; this change does not claim that overhead has been measured. The
native composition root retires the session once, only after `runNative`
returns successfully following the existing drain and actual thread join.
Recorder completion checks must also pass. The document is then encoded and
written synchronously to a new temporary sibling; a move without replacement
publishes the requested path ([CreateFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew),
[MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)).
A failed write is not retried, and the byte limit is not a filesystem latency
deadline. A failed temporary
cleanup may leave that uniquely named `.partial` file, never a published
requested output.

Any startup, rollback, fatal-owner or join throw marks the capture incomplete
without sampling, serializing, writing or attempting new shutdown machinery.
Those errors do not prove that native producers joined. The requested journal
can therefore remain absent on incomplete or fatal capture. The existing app
exit code and error callbacks remain authoritative and unchanged.

Treat journal files as private diagnostic artifacts: they contain request and
window lifetime IDs, PID/TID, device/frame IDs, QPC values and swap-chain
addresses. They contain no HWND, window title, text/input payload, pixel data
or system-wide traffic. No elevation, service, provider, ACL, group, registry,
display-mode change or input injection is performed.

An application Present is not a displayed frame. A successful HRESULT is not
proof of display, visibility, input latency, deadline success or hardware use.
The journal deliberately contains no ETW Start/Stop, display/discard disposition
or input-effect facts. WARP can exercise acquisition plumbing; headless output
cannot establish window Present, and neither qualifies hardware. The issuing
adapter software flag is retained when the existing submission supplies it.

Actual display acquisition still needs a reviewed provider/schema set, capture
access, loss/finalization evidence, a decoder, clock/lifetime association and
display/discard/unknown handling. Input effects, demanded deadlines, quantile
eligibility and hardware/refresh evidence remain separate work. The original
[goal](../goal.md) remains unchanged: baseline 60 Hz and qualified 120/144 Hz,
at least 30 seconds steady interaction with fewer than 1% missed deadlines,
p95 active framework work within one refresh and p95 input-to-present within
two refreshes, plus the original startup and long-session resource evidence.
No journal alone closes any of those requirements.

Microsoft references checked 2026-09-02:
[Present](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiswapchain-present),
[frame statistics](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/ns-dxgi-dxgi_frame_statistics),
[QPC](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps).


At source integration, strict lint on the ten changed Swift files and
architecture checks pass. The 33 new acquisition tests, their combined
77-existing-plus-33-new selection, and actual native execution remain pending.
These new tests use fake clock/backend objects; they do not exercise the actual
D3D11 Present or Win32 file writer. A journal may finalize with no requests, so
positive plumbing evidence must separately require nonempty actual Present
records, completed branch-specific delivery, closed epochs and natural process
closure tied to the compiled source.

The planned automated exercise uses the existing 0.5-second no-input diagnostics
mode only after unit validation, with a separately reviewed bounded controller
and distinct fresh diagnostic/journal files. This interval is shorter than the
existing 1.5-second warmup and cannot supply steady-state performance evidence.
The ordinary demo can write its pacing cache even without input. Its child-only
LOCALAPPDATA will point to a new owned attempt directory, and inherited nonempty
SWIFT_WINDOWSUI diagnostic modes will be refused. This redirects the identified
cache writes; it does not isolate Foundation preferences or external UI actions.
The normal bounded demo-preference read remains. No such native exercise has
been performed at this checkpoint.
