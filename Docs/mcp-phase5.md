# Kalvian Roots MCP Phase 5 Acceptance

## Outcome

Phase 5 adds the read-only `generate_juuret_citation` MCP tool and a
deterministic `JuuretCitationService`. A successful `resolve_person_context`
call now stores its versioned evidence under local Application Support so the
returned `contextId` can be used by the citation tool after a process restart.
An inaccessible context store is a critical cache error; the server does not
silently substitute temporary state.

Every citation result is a `CitationProposal` containing:

- deterministic rendered text;
- the exact indexed arrow target;
- every source span used;
- all unresolved fact conflicts;
- parser, traversal, and completeness warnings; and
- `requiresApproval: true`.

The service makes no AI, HiSki, FamilySearch, or other network calls. The MCP
server has no tool that approves or attaches the proposal.

## Rendering rules

Names and patronymics are rendered exactly as stored in the validated parsed
family. The app and MCP renderer now call shared core rules for English dates,
two-digit marriage years, and footnote display. Missing facts are omitted
rather than invented. Multiple couples retain separate `Additional spouse` and
`Children` sections.

Reference-harvested death and marriage facts may enhance the selected person's
line. A field with unresolved conflicts is not enhanced from a conflicting
referenced claim; the starting-family value remains in the rendered text and
all competing values remain in the proposal's structured `conflicts` array.

The approved page-display policy keeps the starting family's pages in
the opening line and adds a supplemental-source note such as:

```text
Additional information:
Maria's marriage and death dates are on page 204
```

The user approved this wording on 2026-08-19. The policy remains isolated in
one rendering function, and all source spans are retained independently of the
display text.

## SAKERI 4 acceptance case

For Maria, the renderer produces the approved family wording and arrow, uses
her `03.03.1756` value from `SAKERI 4`, and harvests death `04.10.1829` and
marriage `26.12.1782` from `PUUKANGAS 6`. The proposal retains both source
spans and the `03.03.1756` versus `13.03.1756` birth conflict. It does not treat
the FamilySearch progress annotation as book evidence.

## Verification

Run on 2026-08-19 with Xcode 27 beta 5.

The Swift package suite passes 48 tests:

- 38 core tests; and
- 10 MCP adapter tests.

Phase 5 coverage includes exact Maria wording and arrow placement, harvested
facts, conflict preservation, deterministic proposal IDs, source-span order,
parent `as_child` citation selection, multiple spouses, missing dates, exact
selected-person validation, traversal-limit-specific context IDs, durable
context round trips, missing-context errors, MCP discovery, audit behavior, and
mandatory approval.

The full existing macOS app scheme also passed:

- 448 XCTest tests;
- 7 Swift Testing tests;
- 455 total tests;
- 0 failures and 0 skips.

A fresh Codex CLI task using the installed plugin completed the real
`SAKERI 4` to `PUUKANGAS 6` sequence against MCP executable `0.4.0`. It
returned the expected text, `requiresApproval: true`, both source families, and
the birth conflict. The audit records show `validated_hit` followed by
`context_hit`, with no external services contacted. After the page-display
policy was confirmed, the plugin manifest passed validation and was
cache-busted and reinstalled as version
`0.1.0+codex.20260820001632`.

## Phase boundary

Phase 5 formats Juuret citation proposals only. It does not query HiSki, inspect
FamilySearch, resolve genealogical conflicts, approve a proposal, attach a
citation, or modify `JuuretKälviällä.roots`.
