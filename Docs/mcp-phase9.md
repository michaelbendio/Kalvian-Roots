# Phase 9 Acceptance Record

## Result

The FamilySearch-assisted citation workflow is implemented. Its real-person
acceptance gate remains pending because no live FamilySearch action was
performed during implementation.

## Implemented boundary

`CitationReviewService` creates a durable, versioned review record from a saved
single-family workup. Each Juuret or HiSki proposal keeps:

- its exact rendered text and source link;
- the selected person and originating workup;
- source spans, warnings, and conflicts;
- an append-only sequence of approved, rejected, or deferred decisions; and
- an append-only sequence of copied, attached, failed, or deferred outcomes.

Every decision and outcome requires an explicit human-confirmation flag. An
attachment outcome is rejected until that exact proposal is approved, and an
`attached` outcome also requires the FamilySearch person identifier. These
records describe actions reported by the user; the service does not perform the
actions.

MCP exposes:

- `get_citation_review`
- `record_citation_decision`
- `record_familysearch_attachment_outcome`

The two record tools update only the local review ledger. They do not open,
scrape, crawl, or modify FamilySearch.

## Verification

Automated tests verify independent dispositions, rejection without explicit
confirmation, rejection of an attachment outcome before approval, required
person identification for a confirmed attachment, and complete traceability
from an outcome back to the workup, person, and source spans. The complete
Swift package run passes 51 core XCTest tests, 12 Swift Testing workflow tests,
and 13 MCP adapter tests.

The first supervised Kustaa Matinp. (`KLXK-37H`) proposal was rejected. It
revealed three concrete defects that are now permanent regression gates:

- a parent citation must resolve and render the person's `as_child` family;
  it must never fall back to the family where that person is a parent;
- the legacy cache representation `268`, `269` is equivalent for validation
  to the canonical source header `268-269`, while both original
  representations remain unchanged; and
- a HiSki proposal's rendered citation is the canonical app-compatible detail
  URL, such as `https://hiski.genealogia.fi/hiski?en+t4085059`.

`Phase9KustaaAcceptanceTests` uses the exact approved Kustaa Juuret citation
and HiSki URL as golden outputs. It also verifies that an unresolved
`as_child` family stops citation generation with an explicit error. This is
the automated technical acceptance gate for that request; it is not evidence
of a FamilySearch attachment.

The MCP integration test uses only in-memory fixtures. Its example attachment
outcome is not evidence that a real FamilySearch citation was attached.

## Remaining acceptance step

With the VPN off and the user supervising the visible FamilySearch page:

1. Review each proposed citation and record its individual disposition.
2. Copy or attach only an approved proposal through the visible UI.
3. Record the outcome and actual FamilySearch person identifier.
4. Retrieve the review and confirm the complete evidence chain.

Until this happens, Phase 9 is implementation-complete but not acceptance-
complete.
