# GeometryReader construction during a logical List UIA request

The typed logical List request can rebuild an unresolved `GeometryReader`
without dropping the original UIA preparation. This applies both to raw runtime
readers and to the public `List` path with mounted State. It does not increase
the shared element or round allowance, and by itself does not resolve the
separate default four-round far-row regression.

`RetainedLazyListUIAContinuationAuthority` is captured before the first reader
lease getter or body. It holds native identities and weak references to the
original runtime, preparation, and optional request. Its checks preserve the
original request phase, pass and resolution sequence, local layout witnesses,
target attachment, source generation, focus and pointer state, scroll intent,
and display-scale identity. Weak expiry or replacement rejects that operation;
it cannot fall back to ordinary construction or adopt a newer preparation.
The first rejection also stops the exact original preparation, so another
reader cannot capture fresh geometry and resume the same failed request.

The same immutable optional authority travels through the transient descriptor
journal and node reconciliation checks. The guard is separate from an ordinary
journal's optional metadata: adding UIA admission does not turn ordinary
metadata into a managed-publication requirement. Nil-authority calls keep the
existing ordinary matching and publication rules. No UIA authority is installed
in accepted rows, mounted State, deferred leases, permanent task declarations,
or completion witnesses. A completed request therefore does not expire an
otherwise live row's later ordinary reader rebuild or State binding.

Checked reconciliation tests the original native proofs after each entered
callback and before later work. This includes key hashing and equality,
controller attach/reconcile, scroll-observer transfer, task cancellation before
a replacement task, property payload release, and child attachment. Completed
subtrees remain obligations of the operation while later siblings run. A larger
completion may replace earlier ones only after every old and incoming witness
is current and its captured fields exactly cover the earlier witnesses; a new
snapshot cannot hide an earlier child's identity reassignment.

Reader body, lease, epoch, and throwaway candidate scopes unwind before a final
native audit. Before publication, the audit checks the original construction
fields. After publication, it checks the exact resulting body/lease identities,
resolved build size, and full accepted subtree. Capturing that result changes
neither the original UIA permission nor the earlier completion obligations.
Native identity markers detect assignments that restore the same value,
including body/lease replacement and display-scale changes.

Revocation stops new work, not cleanup already owed by an entered build. The
ordinary long-press epilogue, accepted partial publication, epoch finish,
accepted task cleanup, unadopted transport release, and coordinator exit still
run. A request that loses authority reports failure even if a valid accepted
prefix remains mounted. A later independent request can make progress only
through its own preparation.

The supporting `RetainedViewIdentity.Key` correction specializes recursive
checks only when `AnyHashable.base` has exactly the framework's identity, key,
or segment type. Conditional casts alone can unwrap an optional and change
ordinary equality. Other erased values retain the original `AnyHashable`
hashing and equality, including numeric canonicalization. An opaque or optional
composite remains one entered operation; this does not promise cancellation
between callbacks hidden inside that operation.

The source regression coverage includes raw and leased reader positives,
false/nil callback results, candidate-release callbacks, same-value identity and
scroll changes, completed-descendant mutation, and public List reader/State
survival. The managed close case captures a weak real State epoch while the
deferred reader build is active and requires its release before the UIA call
returns, while the closed host is still retained. Registry closure alone is not
the cleanup oracle.

The earlier unlanded test that required every unresolved reader to stay
uninvoked represented the temporary refusal of valid reader construction. Its
successor keeps the same positive-size setup and original request provenance,
and now requires the authorized rebuild's body count, size, settlement, and
absence of premature far-row work. Existing invalid-reader, old budget, and
predecessor-gap safety tests are retained. Source review and formatting do not
establish a runtime pass: compilation, the original failing default-budget
case, and the complete affected test set require separate serial validation.
