# Retained alerts

The public Boolean, item, builder, and error alert overloads use one retained
alert implementation. Both absent and presented alerts have the same host shell
and base-child slot. The overlay does not replace the background editor or its
mounted State. Legacy Alert buttons, builder Buttons, and generated OK use the
same action-before-reset operation; they do not stack independent reset handlers.

Hosted alerts participate in the existing PresentationActivity ledger owned by
StateMountCoordinator. An alert slot can survive an absent presentation, but
its active generation cannot survive an accepted dismissal, item-ID replacement,
inactive subtree removal, or host close. Deferred GeometryReader builds use the
existing accepted reader lease and activity boundaries. Constructed but rejected
content never acquires action authority. Preparation suspends authority before
reconciliation callbacks; abandonment restores the prior accepted generation.

Each constructed action has its own accepted receipt. An escaped old activation
or repeat closure cannot run a removed Button merely because its alert remains
presented. Once an action starts, its operation separately pins the admitted
action and captured reset. An ordinary same-alert State rebuild can replace the
Button while that operation finishes; replacement or close cannot retarget its
reset to a new alert. Reentrant activation is suppressed. A custom binding that
refuses reset leaves the alert modal and permits a later separate user attempt.

The alert's `presenting:` payload is a value snapshot for one accepted hosted
generation. Later values, including nil, do not replace that snapshot while the
Boolean presentation remains active. This is not a deep copy of reference data.
Empty actions supply OK, without inventing an extra Cancel button. These policies
follow the [Apple alert documentation](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:)-29bp4).
Precise native callback ordering and visual equivalence still require native
reference evidence.

Focus restoration is authorized by an accepted, materialized absent shell, not
by setting a Boolean or removing a modal trait early. A revocable request waits
for the existing retained build settlement mechanism and fresh layout/prepaint.
It resolves the actual retained base and the original eligible focus target,
without stealing another focus intent or a replacement modal. Requests remain
parked during keyboard dispatch. Focus-exit/enter callbacks can reenter, replace
the tree, or close the owner; primitive ownership and focus revisions are checked
again before completing. No timer, Task, polling loop, or continuing render loop
is used to obtain settlement.

Framework markers travel through existing retained preference storage during
reconciliation. Action receipts and layout/key handlers do not retain a source
construction node, runtime, or application action. The accepted owner holds the
actions only while needed. Closing first revokes every alert action and focus
request, then mounted State writes, before releasing application captures. Sheet
dismissal order, interactive focus behavior, and tests remain separate and unchanged.

Raw Component and snapshot clients can build actionable alerts in a live attached
RetainedViewRuntime, including reusing one Component in multiple runtimes. Each
raw materialization owns its own receipts. A detached construction node or a node
whose runtime has been released is not an actionable presentation. Tests that
invoke alert actions must retain the runtime and attach the node, not keep only a
discarded construction node. Raw clients do not acquire hosted State ownership,
accepted-epoch replacement/abandonment semantics, hosted payload persistence, or
post-removal focus restoration merely by constructing a Component.

Boolean Binding has no source identity. An equal-true rebound binding or an
unobserved false-to-true change is not proof of a new accepted presentation. No
public binding provenance is invented. Code needing an exact external operation
identity must keep its own captured action/reset guard; the document decision
adapter's presentation UUID is one such guard. Item alerts additionally use their
typed ID and accepted generation, without stringifying IDs.

This slice does not implement document IO, unsaved-close decisions, native
activation-character suppression, or UI Automation action isolation. Those
separate integrations must be validated with this mechanism before a complete
document workflow is advertised. Tests authored for this change are not execution
evidence until the integration checkout compiles and runs them.
