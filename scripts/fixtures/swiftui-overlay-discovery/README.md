# Synthetic overlay definition parser fixtures

`parser-cases.json` contains synthetic inputs for the approved
`swiftcrossimport-canonical-v1` auditor profile. These are parser contract cases,
not SDK captures, native compiler observations, or API/behavior qualification.

Each row has a unique `id` and maps to one of the ten `definition-parser` case IDs
in the approved follow-up plan's failure matrix. Multiple rows exercise the same
planned case; they do not add a new discovery root, native probe, or parser mode.

Encode `text` as strict UTF-8 with no automatically added BOM, or decode
`base64` directly into bytes. Exactly one input field is present in every row.
A literal U+FEFF at the beginning of decoded `text` supplies the optional UTF-8
BOM itself. Do not normalize newlines, trim text, repair malformed byte sequences,
or strip a BOM in the fixture loader.

Pass each optional `limits` member to the corresponding parser parameter:

| Fixture member | Parameter | Default |
| --- | --- | --- |
| `maximumBytes` | `MaximumBytes` | 1048576 |
| `maximumLineBytes` | `MaximumLineBytes` | 65536 |
| `maximumNames` | `MaximumNames` | 4096 |

Compare `expectedStatus` exactly. Compare `expectedNames` with the returned
`nameOccurrences` in order, including duplicates and case, and check consecutive
zero-based `index` values. No failed or unsupported parse returns partial names.
An empty expected array means an empty definition only when the status is
`parsed-canonical-v1`; otherwise it is an unsuccessful interpretation.

`unsupported-format` means the input is outside this deliberately limited
auditor profile. It is not a claim that the pinned Apple compiler rejects the
input. In particular, version zero, null values, quoted scalars and flow
collections must not be silently coerced into canonical success.
`invalid-to-profile` covers missing/unknown/duplicate required mapping fields
and malformed UTF-8. `limit-reached` means an explicit byte or occurrence budget
was exceeded, not that a truncated result is usable.

Mapping keys may occur in either order and exactly once. Items use the approved
two-space block spelling. Repeated names remain distinct source occurrences.
The boundary pairs use small explicit budgets: the same bytes pass at N and
fail at N-1. Total bytes include the BOM and line terminators; the line-budget
pairs use LF without a BOM and count the line content bytes. A multibyte comment
guards against counting UTF-16 characters instead of UTF-8 bytes.

The caller that produces a discovery report remains responsible for retaining
the original bytes and their hash even when decoding fails. These fixtures
assert parser results only; their definitions and expectations do not prove a
filesystem census, native loading, or overlay completeness.
