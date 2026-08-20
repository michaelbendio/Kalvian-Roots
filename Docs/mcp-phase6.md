# Kalvian Roots MCP Phase 6 Acceptance

## Outcome

Phase 6 adds a shared deterministic `HiskiResearchService` and three read-only
MCP tools:

- `build_hiski_query` constructs birth, marriage, and death searches;
- `search_hiski` retrieves and parses a result page; and
- `get_hiski_record` retrieves one detail record and its canonical citation
  link.

Every query retains the selected Juuret person, motivating field and value, and
the exact Juuret source span. Requested source names remain separate from the
query-only first-name form. The query-name exceptions, date expansion, search
parameters, `sl.gif` selector, and detail citation extraction are now shared by
the existing app and MCP implementation.

## Evidence and ambiguity

Result parsing is deterministic and header-driven. A candidate retains the
ordered field labels and values as displayed by HiSki, a readable row copy, the
`sl.gif` detail path, and the absolute detail URL. The result retains a SHA-256
of the downloaded or saved HTML.

All matching rows are returned. Two rows on the requested date set
`ambiguous: true` and emit `ambiguous_hiski_candidates`; the service never
chooses an identity. Detail records retain the motivating query and its Juuret
provenance, their displayed fields, readable text, response hash, and canonical
`https://hiski.genealogia.fi/hiski?en+t...` link.

## Network boundary

`build_hiski_query` has no network access. Both live tools require
`allowLiveNetwork: true`; omitting it or passing false returns
`approval_required`. Live URLs are restricted to HTTPS on
`hiski.genealogia.fi/hiski`, detail targets must have the event-specific shape
produced by an `sl.gif` row, responses are limited to 2 MB, and every attempted
live call is recorded in the MCP audit.

The normal suite uses saved HTML for birth, marriage, death, and detail pages.
The separate live smoke test runs only after the user confirms the VPN is
ready:

```sh
cd /Users/michaelbendio/KRoots.dsh/KalvianRootsCore
DEVELOPER_DIR=/Users/michaelbendio/Downloads/Xcode-beta.app/Contents/Developer \
  RUN_HISKI_SMOKE=1 swift test --filter HiskiResearchServiceTests/testLiveSmokeWhenExplicitlyEnabledAndVPNReady
```

## Current verification

Run on 2026-08-19 with Xcode 27 beta 5:

- 44 core tests passed;
- 11 MCP adapter tests passed;
- all 55 package tests passed;
- the complete existing app test scheme passed; and
- the tool catalog is valid JSON.

The opt-in live smoke remains pending VPN confirmation. Phase 6 is not marked
fully accepted until that test succeeds.

## Phase boundary

Phase 6 returns research evidence, not proof of identity. It does not compare
raw HiSki rows directly with Juuret or FamilySearch objects, create final HiSki
citation proposals, approve a citation, access FamilySearch, or modify the
canonical Juuret source.
