# Dashboard local data workflow

The dashboard's existing Render pipeline chart now has a real local JSON read
and decode workflow. Its initial authored chart is labeled **Preview data**;
constructing the model starts no work and does not report a successful load.
The existing range buttons, per-column hover, and activity-driven sample values
remain in place. These are sample metrics, not measured renderer telemetry.

The shared demo uses the same SwiftUI-shaped source on macOS and Windows.
`DemoDashboardModel` owns `DemoDashboardDataModel`, and the chart observes that
data model directly. There is no renderer-specific drawing API, platform
workaround, network dependency, background polling, or global cache in this
workflow.

## Using the controls

Choose an **Input**, then press **Refresh**:

- **Valid** reads and decodes the built-in report with 10 daily, 7 weekly, and
  12 monthly points. Its values deliberately match the original preview.
- **Empty** reads a valid report whose three arrays are empty. The chart shows
  an empty message instead of retaining old marks or substituting preview data.
- **Malformed** reads truncated JSON. The actual decoder rejects those bytes,
  and the status explains the failure.

Input selection by itself does not read anything, change the displayed report,
or relabel an outstanding request. **Refresh** uses the selected input.
**Retry**, available after failure or cancellation, rereads the input of that
failed or cancelled request. Retrying the built-in Malformed input fails again;
choose Valid and Refresh for recovery, or repair an injected store before Retry.

**Cancel** immediately revokes permission to publish the current result. A
cancelled read still occupies its physical slot until the reader returns. The
status distinguishes that draining read from one that has finished. Refresh
during a read cancels the old request and keeps only the latest replacement;
the replacement cannot start until the old call returns. Cancel also discards
any waiting replacement.

The current chart stays visible while a read is loading, fails, or is cancelled.
A successful report replaces it, including when the report or selected range
is empty. The status is independent from the chart content so that a retained
preview or previous report is never described as a newly successful result.
Range selection survives the update and filters the decoded day/week/all arrays.

The built-in inputs are small and may finish before a pointer can reach Cancel.
There is no artificial sleep, progress increment, or forced success/failure to
keep a status visible. The new source tests hold actual byte delivery through
an injected reader to exercise loading, cancellation, retry, and late results
deterministically.

## Bounded data and work

`DemoDashboardDataService` performs the read and decode on its actor, outside
the UI actor. It admits one physical read/decode call at a time. A second caller
receives a busy error; the service has no pending queue and creates no detached
tasks. Cancellation propagates through the same caller task, and admission is
released only when that call actually returns. A custom reader that does not
cooperate with cancellation can delay replacement work; it cannot cause the
model to create more physical jobs.

The model owns one job and at most one latest pending request. Every request has
a diagnostic UUID and a distinct internal identity; only the current identity
may publish a report, error, or cancellation. The task does not retain the model
across the reader suspension. Closing the model revokes intent, releases its
displayed report, cancels the job, and permanently rejects further actions.
Releasing the model also cancels its job. A tab change does not close this
application-owned model, which can be shared by more than one dashboard view.

The decoder accepts only schema version 1:

```json
{
  "version": 1,
  "day": [{"label": "Frame 1", "fraction": 0.5}],
  "week": [],
  "all": []
}
```

The complete encoded input is limited to 16,384 bytes before JSON parsing.
All three arrays are required; each permits at most 12 points, so a retained
report contains at most 36 points. Labels must be nonempty single-line text,
contain no control characters, fit within 24 UTF-8 bytes, and be unique within
their range. Fractions must be finite and between zero and one, inclusive.
Wrong types, missing fields, invalid versions, excess points, and invalid
labels or fractions produce visible failures, not truncated success.

The decoder keeps no raw byte history. Temporary JSON decoding allocations are
bounded by the encoded-input cap; only the validated report is retained after
the read. A replacement reader must enforce its own allocation/read limits
before returning bytes. The service cannot undo allocations made inside an
application-supplied adapter.

Decoded fractions feed the original view-based chart. As before, dashboard
activity adds a deterministic phase adjustment of less than 0.1 and scales the
result to a maximum of 40. Unlike the authored preview's minimum mark value,
a decoded zero remains zero at rest. This adjustment changes presentation only,
not the stored report. A range with no points remains empty.

## Extension point

Inject a service into the data model, then into the ordinary dashboard model.
The adapter returns encoded bytes; it cannot inject a successful model state or
bypass the decoder. For example, this supplies a different bounded local report
while preserving the built-in empty and malformed examples:

```swift
let localBytes = Data(
    #"{"version":1,"day":[{"label":"Local","fraction":0.75}],"week":[],"all":[]}"#.utf8)
let service = DemoDashboardDataService { sample in
    try Task.checkCancellation()
    return sample == .valid ? localBytes : DemoDashboardDataService.encodedSample(sample)
}
let dataModel = DemoDashboardDataModel(service: service)
let dashboard = DemoDashboardModel(dashboardData: dataModel)
```

Create the UI-facing models on the main actor. An asynchronous local-store
adapter uses the same closure, bounds its reads, checks cancellation, and
eventually returns or throws. Arbitrary adapter errors are presented as a
generic read failure; error objects and private file paths are not retained or
displayed. `DemoDashboardDataService.decode` is also available to validate new
sample bytes without starting an asynchronous request.

## Validation boundary

New source fixtures are `DemoDashboardDataModelTests` and
`DemoDashboardDataInteractionTests`. They cover real decoding and limits,
request replacement, physical-slot draining, stale completion rejection,
model release, shared-service admission, observer reentry, and public retained
Refresh/Retry/Cancel/range/hover controls. The retained fixture registers real
observation-center tokens and reloads synchronously on notification; it does
not substitute a manual model-success assignment for decoding. It does not
exercise the native window host's frame scheduling.

The implementation packet was authored without compiler, formatter, test,
gallery, or native execution. These source fixtures are not passing-test or
visual evidence until the integrating task runs them. Existing test files and
gallery baselines are unchanged. Native scheduling and accessibility,
composited visual review, macOS shared-source execution, and broader dashboard
and original-goal qualification remain separate requirements.

The existing demo Sync and component-diagnostics actions are separate from this
loader. Sync currently advances a sample progress value, and diagnostics records
a demo event; neither is qualified as real synchronization or diagnostic work by
this change. Existing chart activity effects change presentation, not the decoded
report. Those behaviors remain separate original-goal work.
