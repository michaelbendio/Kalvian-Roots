# Kalvian Roots MCP Phase 4 Acceptance

## Outcome

Phase 4 is complete. The Swift MCP executable now exposes five read-only tools,
including the new:

- `resolve_family_references`; and
- `resolve_person_context`.

Both tools use the shared deterministic `FamilyNetworkService`. They do not use
AI to match people, follow references, harvest facts, or identify conflicts.
DeepSeek remains available only through the Phase 3 parsing service when a
referenced family is absent from both validated cache tiers.

## Resolution rules

Traversal follows only explicit `asChild` and `asParent` values. It is bounded
by `maxFamilies`, `maxDepth`, and `maxElapsedSeconds`; a reached family or depth
limit produces an explicitly incomplete result rather than an inferred graph.
Families and edges retain source order.

Person matching requires the exact parsed given name plus either compatible
birth evidence or the expected spouse relationship. A FamilySearch progress ID
may break a tie, but it is not an identity key and is not treated as book
evidence. Name alone is never sufficient. Patronymics remain exact source
context and are not identity keys.

The service reports:

- missing, malformed, mismatched, and ambiguous reference targets;
- cycles;
- traversal limits;
- unexpected duplicate exact-name-and-birth identities;
- unexpected duplicate FamilySearch progress IDs;
- every direct and reference-harvested birth, death, and marriage claim; and
- conflicts containing every competing claim without a selected winner.

Every claim carries the source family, pages, line span, block hash, parsed JSON
field path, schema version, parser implementation version, and derivation.
Abbreviated and complete marriage dates with the same year are retained as
compatible claims rather than reported as a false conflict.

## SAKERI 4 acceptance case

The installed Codex plugin called `resolve_person_context` for Maria at
`SAKERI 4`, couple 0, child 0. The bounded result accessed:

1. `SAKERI 4`, pages 265 and 266; and
2. `PUUKANGAS 6`, page 204.

It returned Maria's direct `03.03.1756` birth claim and harvested:

- death `04.10.1829` from `PUUKANGAS 6`, page 204; and
- marriage `26.12.1782` from `PUUKANGAS 6`, page 204.

It preserved the `03.03.1756` versus `13.03.1756` birth disagreement as a
`birthDate` conflict and reported the reverse reference as the cycle:

`SAKERI 4 -> PUUKANGAS 6 -> SAKERI 4`

The second acceptance call was a validated cache hit. Its audit record reported
MCP executable `0.3.0`, no external service contact, the cycle warning, and the
birth conflict. The accumulated schema-2 cache remained the bootstrap source;
no bulk regeneration occurred.

## Verification

Run on 2026-08-19 with Xcode 27 beta 5.

The Swift package suite passed 39 tests:

- 31 core tests; and
- 8 MCP adapter tests.

Phase 4 coverage includes Maria's harvested death and marriage claims,
field-level provenance, compatible abbreviated marriage years, birth conflict,
cycle termination, missing references, target mismatch, name-only rejection,
repeated-name selection by indexed reference, duplicate identity and ID
warnings, explicit depth limits, discovery, structured responses, and audit
behavior.

The full existing macOS app scheme also passed:

- 448 XCTest tests;
- 7 Swift Testing tests;
- 455 total tests;
- 0 failures and 0 skips.

The canonical source SHA-256 remained unchanged:

`3accc9e3cca9d2940798c7ff78fdb635e52564a806876501079ae145e67dd486`

The plugin manifest was validated, cache-busted, and reinstalled as
`kalvian-roots@personal` version `0.1.0+codex.20260819231636`.

## Phase boundary

Phase 4 returns structured evidence and conflicts. It does not render Juuret
citations, query HiSki, contact FamilySearch, modify the canonical source, or
approve any downstream action. Deterministic citation formatting remains Phase
5.
