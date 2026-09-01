# Owned native UIA actor dispatch

The owned native smoke at `26390ef2f30b4aeb8cf022ab998eb5a14e7fbfd7`
recorded retained actor-query work on the blocked native owner and on the
external COM caller. The old typed dispatch used `DispatchQueue.main.sync`
followed by `MainActor.assumeIsolated`. A borrowed main-queue context did not
establish the required separation from those calling threads. The retained
trace under
`artifacts/goal-ninth-native-owned-smoke-32ffa69ae7554d8fbc92aea2a6b33f6f`
is failed evidence, not actor/native separation or successful shutdown.

`UIANativeRequestDispatch.perform` now retains the original full C-call lease,
obtains the callback context, reads and validates the original owner snapshot,
and builds the same immutable request envelope before dispatch. For a foreign
caller, an ordinary `Task { @MainActor ... }` owns that envelope, context,
lease, and reply cell through the complete non-suspending receive. It does not
refresh geometry after the hop, batch callbacks, bypass a retained projection,
or ask the native owner to make progress.

The reply cell distinguishes pending from completed with an optional reply.
A nil reply is therefore a completed failure, not an unfinished request.
Completion is claimed under a short mutex and signaled after unlocking. The
foreign C caller waits without holding that mutex. The signal occurs only
after receive has returned, its existing transaction defer has run, and the
native actor-entry scope has ended. There is no production timeout,
cancellation shortcut, native message pumping, or raw output pointer captured
by the task. The original `ProviderCall` continues to own C marshalling after
the Swift callback returns; queued work owns an additional full-call lease,
so native quiescence cannot race unfinished actor evaluation or publication.

An actor already making a synchronous C query cannot block awaiting itself.
The internal `UIANativeActorEntry.withScope` wrapper makes that call boundary
explicit. Its synchronous, nonescaping `@MainActor` body is invoked within a
tiny C++ thread-local RAII scope. Nested scopes restore their predecessors;
none can span an await or propagate to another thread. A temporary Swift
invocation box erases the generic result for the C callback, remains owned by
the wrapper, and is not retained by C. An optional result uses an outer
completion value, so a nil body result is still a normal return.

The scope records an already-established actor call chain. It does not prove
actor isolation by itself, infer it from a thread or queue, or grant provider
admission. The only production scope entry is inside the ordinary queued
receive. The other existing entries are the explicitly inventoried genuine
actor-to-C calls in two headless owned fixtures. No marker is installed by
`Thread.isMainThread`, a queue label, `TaskLocal`, a cached thread ID, legacy
`onMain`, the shared smoke-provider query, or its worker callers. There is no
new public Swift wrapper or unsafe executor API.

An owned callback may use the synchronous inline receive only while that
native lexical scope is active. All original lease, window, surface, weak
bridge, revocation, and post-callback checks still apply. The witness is not
keyed to a provider family: a different-family nested request must reach the
same existing actor-wide `nativeRequestInProgress` guard and return `E_FAIL`,
rather than enqueue work that the current actor call would then wait for.

The two existing owned fixture files retain their 16 and 10 test methods and
all existing C calls, arguments, output buffers, HRESULT assertions, query
counts, loops, far-item traversal, and realization budgets. Fifteen actor name
queries use a separate actor-only wrapper; the shared raw name helper and its
detached worker remain unchanged. Twelve direct request-fixture C calls,
five actor-only item helpers, and ten direct item-fixture C calls enter the
synchronous scope. Scope wrappers never cover a whole async test or a fixture
lifetime. Source review removes these explicit adaptations and compares the
remaining fixture tokens, assertions, C calls, loops, and worker code to the
original committed sources.

`UIANativeActorDispatchTests` adds ten separate async regressions for a real
foreign-thread query, explicit outer actor calls, same-family and
different-family nested failures, revocation with a completed nil reply,
full-call lifetime through the C publication gate, nested scope restoration,
non-propagation to another thread, optional nil results, and one-shot reply
completion. Their native functions are headless except for local synchronization
primitives. They do not create an HWND, call native UI Automation, or pump
messages. The scope-propagation worker only reads its own TLS while the actor
scope remains active; it never makes a query that could wait on the actor.

Arbitrary new synchronous raw-C actor interoperability must explicitly enter
the internal scope at a genuine actor boundary. Reaching a C callback cannot
automatically establish that origin. In particular, an external caller that
already holds a borrowed synchronous main-queue context cannot safely block
asking that same actor to run. These direct-vtable fixtures make no claim
about cross-thread COM apartment forwarding.

This repair is a separate source commit above the owned-root shutdown repair.
At handoff, neither it nor its new tests has been compiled or executed.
Read-only strict formatting, static preservation checks, and architecture
contracts are source evidence only. The existing 45 smoke regressions, 27
validator predicates, 64-command native workload, timeouts, and earlier sealed
shutdown packet remain unchanged. Integrated-HEAD compilation and tests plus
a fresh exact-bound native smoke remain required. Ingress fairness is still
unexercised; this repair does not qualify Narrator, routed COM, pixels, pacing,
or long-duration idle behavior.
