# Phase 10 Acceptance Record

## Result

The Juuret Project pilot-reporting and operating foundation is implemented.
The real pilot and the user's scale-up decision remain pending.

## Pilot contract

A pilot is explicitly defined by a name, one bounded traversal session, a set
of one to twenty-five allowed families, and the citation-review records within
that family set. `PilotService` refuses families outside the traversal allow-
list and review records outside the pilot family set.

The versioned report retains the source revision and source spans, completed
families, reasons incomplete families did not finish, unresolved conflict
fields, citation-review identifiers, metric status, and readiness history.

MCP exposes:

- `create_pilot_report`
- `get_pilot_report`
- `refresh_pilot_report`
- `record_pilot_readiness`

## Measurement discipline

The report measures family completion, recorded DeepSeek calls, network
failures, unresolved conflicts, human-recorded citation dispositions, review
elapsed time, and confirmed attachment outcomes. Parsing accuracy and reference-
resolution accuracy remain `pending_human_review` until a person evaluates them.
AI cost remains `unavailable` because token usage and provider pricing are not
currently retained. No percentage or cost is invented.

Broader traversal is blocked while readiness is pending or not ready. Only an
explicit human-confirmed `ready` decision with a rationale removes that report
flag.

## Verification

Tests cover measured versus pending metrics, incomplete-family reasons,
definition boundaries, and the explicit readiness gate. The full package run
passes 48 core XCTest tests, 12 Swift Testing workflow tests, and 13 MCP adapter
tests. Operating procedures are recorded in `mcp-operations.md`.

## Remaining acceptance steps

1. Select a meaningful, bounded real family set.
2. Complete the defined family's HiSki research through the accepted live path.
3. Human-review parsing, reference resolution, matches, and citations.
4. Complete the supervised Phase 9 attachment step where appropriate.
5. Refresh the pilot report and document errors and unresolved conflicts.
6. Record the user's explicit ready or not-ready decision.

Phase 10 remains acceptance-pending until those steps are complete.
