# Grid layout

`Grid` uses a retained shared-track layout instead of a vertical stack of
independent horizontal rows. This is a bounded implementation of the existing
facade, not full pinned SwiftUI API or behavioral parity.

## Measured behavior

The runtime measures cells across every direct `GridRow` before placing rows.
Single-column cells establish column requirements; a row's tallest cell or
ordinary alignment-guide extents establish its height. Short rows leave trailing
columns empty without constructing placeholder nodes. A `gridCellColumns(_:)`
span consumes contiguous tracks and their internal spacing. Direct children
outside a `GridRow` occupy a full-width row.

Grid and GridRow use the same explicit structural-child expansion as retained
stacks. Plain `Group`, `ForEach`, and structural view bodies can therefore emit
multiple direct rows or cells through the normal Component and State installation
path. A real layout container, such as a frame or padding wrapper, remains one
child; the runtime does not search its descendants for rows. A nested Grid has
its own independent tracks.

Cells are first measured intrinsically, then measured at their assigned span
width to account for wrapping, and finally offered their resolved cell height.
Flexible columns or rows can take remaining finite space. The corresponding
`gridCellUnsizedAxes` bit suppresses that flexible demand, while the cell can
still fill dimensions established by other cells. The current policy preserves
fixed and intrinsic demand rather than zeroing it solely because an unsized bit
is set.

Grid alignment supplies horizontal and vertical defaults. A non-nil GridRow
alignment overrides the vertical component; nil inherits it. One
`gridColumnAlignment` modifier supplies a column's horizontal alignment.
`gridCellAnchor` aligns corresponding normalized view/cell points. Ordinary
cells use retained alignment guides; merged cells use equivalent standard
anchors. Physical child order does not change for right-to-left layout.

`gridCellColumns` stores span metadata and does not alter an authored layout
priority. This replaces the old growth-priority surrogate.

A finite fixed frame keeps its accepted size when a Grid track is compressed
below that size. Alignment positions the cell within the smaller track; it does
not shrink the fixed content. For example, two 78-point cells in 75-point rows
with 10-point spacing have row origins 85 points apart and centered cell origins
of -1.5 and 83.5. Fixed dimensions do not introduce a new track minimum. This is
the local compression policy covered by `WinSwiftUIGridLayoutTests`, not a
recording of native SwiftUI behavior under the same proposal.

## Explicit policies and remaining limits

The pinned native declarations and Apple documentation establish the shared
track, span, alignment, and unsized-demand concepts. They do not establish the
general numerical solver. The following are explicit implementation policies,
not results from running the pinned native SDK:

- Under a spanning width deficit, each covered logical column receives an equal
  increment. Equal-length underdetermined spans are processed in authored order.
- Compression initially removes proportional slack above retained text and
  declared-minimum floors. Aggregate spanning minima are then restored, even
  when that requires the recorded content to overflow the parent's proposal.
  General heterogeneous minimum/maximum/flexibility/priority negotiation remains
  uncharacterized. Layout priority is preserved but is not used to solve Grid
  columns in this slice.
- Nil horizontal and vertical spacing still resolve to zero. Native nil spacing
  is platform appropriate; no exact native constant is claimed here.
- GridRow outside the Grid build context retains the existing HStack fallback.
  Native GridRow behaves like Group outside Grid; that difference remains open.
- Standard leading/trailing alignment and logical column order mirror in RTL.
  Explicit unit-point coordinates remain physical in the current policy. Exact
  native RTL anchor behavior still requires characterization.
- A spanning cell uses Grid's default standard alignment for its automatic
  anchor. Alignment spanning differently aligned columns, overrides placed on
  spanning cells, repeated modifiers, and merged custom-guide/baseline conversion
  remain open. Apple explicitly leaves conflicting column overrides undefined;
  the implementation's choice is not a native precedence guarantee.
- Invalid/nonfinite spacing is sanitized to zero. Span counts below one retain
  the existing normalization to one. Overflowing span arithmetic saturates
  defensively. Huge spans use observed cell boundaries instead of allocating
  one entry per empty logical column. These rules provide finite defensive
  behavior and do not characterize native invalid-input semantics.

The facade's existing nongeneric Grid/GridRow representation also remains
different from the full generic native public surface. This change does not
close that API gate or any other original release gate.

## Retained identity and layout settlement

`ViewLayoutMode.grid` and `.gridRow` have distinct reconciliation categories.
The host also compares configuration inside those categories, so an installed
Grid receives changed spacing, direction, and alignment without replacing its
mounted cell state. Ordinary stack reconciliation is unchanged by this slice.

The Grid's resolved plan contains geometry and node identity values. It retains
no construction node, callback, State owner, or build context, and the host does
not copy it from a throwaway source tree. Layout and child mutations invalidate
shared measurements and the placement plan.

If an installed Grid's existing plan is invalidated during active layout, the
runtime clears it first and schedules one coalesced, capture-free empty action
through the existing after-layout queue. This requests a bounded settlement pass
when a late row callback changed widths used by earlier rows. Merely assigning
resolved geometry does not request settlement. The existing settlement and
revocation guards remain authoritative, including their refusal to accept
continually mutating geometry. An empty queued follow-up may still run after
detachment; it retains no node payload.

## Regression coverage

`RetainedGridLayoutTests` uses literal geometry to exercise shared intrinsic
tracks, independent spacing, rows and spans, flexible/unsized demand, alignment
metadata changes, baseline guide extents, nested grids, wrapping, minimum-size
overflow, large defensive spans, and bounded settlement. Its wrapping case uses
the existing synthetic text-measurement seam and restores the previous override;
it is not a native typography comparison.

`WinSwiftUIGridLayoutTests` exercises the facade through the existing in-memory
ComponentHost/StateMountCoordinator fixture. It covers Group/ForEach expansion,
nil row alignment, cell modifiers, nested grids, RTL policy, reloads, and an
actual projected State binding whose value survives fresh authored seeds.

The two old facade tests that required Grid-to-stack mapping and span-to-growth
priority were migrated to the new mode/span contracts. The existing standalone
row and metadata-storage tests remain as preservation cases. Focused test
execution, broad validation, and native comparisons are separate evidence;
source coverage alone is not a passing test result.

The 170 selected async XCTest methods passed at independent commit
`73c23ad54c4358e2622f2548e63c79be7c4fff3a`: 36 new Grid cases and 134 preservation
cases, including the two fixture migrations. Its complete 5,459-entry XCTest
registry was reconciled, but the full suite was not executed. No SwiftTesting
tests were selected, and native behavior was not compared.

The unchanged Grid production and test delta is now composed onto committed base
`46d22ffacf7221c1cdc689d7995b37ddaf0a484a`. This combined source is **runtime
UNRUN**. Source contracts, strict lint, and patch-preservation checks are separate
evidence; they do not transfer the prior pass to this combination or later root
integration. All native and implementation-policy qualifications above remain.

## Primary references

Declaration evidence uses the captured Xcode 26.6 (17F113), macOS SDK 26.5
(25F70), Swift 6.3.3 interfaces. Both macOS SwiftUI interfaces contain the same
Grid/GridRow declaration block at lines 17523-17578. GridRow's initializer has an
optional vertical alignment defaulting to nil. Current website declaration
syntax can differ from that pinned capture.

- [Grid](https://developer.apple.com/documentation/swiftui/grid)
- [Grid initializer](https://developer.apple.com/documentation/swiftui/grid/init%28alignment%3Ahorizontalspacing%3Averticalspacing%3Acontent%3A%29)
- [GridRow initializer](https://developer.apple.com/documentation/swiftui/gridrow/init%28alignment%3Acontent%3A%29)
- [Column spans](https://developer.apple.com/documentation/swiftui/view/gridcellcolumns%28_%3A%29)
- [Unsized axes](https://developer.apple.com/documentation/swiftui/view/gridcellunsizedaxes%28_%3A%29)
- [Column alignment](https://developer.apple.com/documentation/swiftui/view/gridcolumnalignment%28_%3A%29)
- [Cell anchors](https://developer.apple.com/documentation/swiftui/view/gridcellanchor%28_%3A%29)
