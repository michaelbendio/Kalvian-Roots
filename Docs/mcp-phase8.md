# Kalvian Roots MCP Phase 8 Acceptance

## Outcome

Phase 8 adds a bounded, resumable family work queue around the existing exact
book-text and validated family-parsing services. A traversal session is tied to
one canonical source SHA-256 and has an explicit family allow-list, maximum
family count, maximum depth, retry count, batch size, minimum interval, and
DeepSeek and HiSki call budgets.

Three read-only MCP tools expose the coordinator:

- `start_family_traversal` creates or returns the same deterministic session
  for the same source, starting families, and policy.
- `resume_family_traversal` processes only the next configured batch and saves
  a checkpoint before and after each attempted family.
- `get_family_traversal` reads the current durable checkpoint without doing
  work or contacting an external service.

The default worker obtains exact family blocks through `BookTextService`, uses
the existing accumulated parsed-family cache through `FamilyParsingService`,
and extracts only explicit `as_child`, `as_parent`, and spouse-parent family
references. It does not create a second parser or genealogy model.

## Failure and recovery behavior

Queued family identifiers are normalized only for deduplication; returned
source identifiers retain their spelling. References outside the explicit
allow-list, beyond the depth limit, or beyond the family limit are not queued.
Back-references and repeated references cannot create duplicate work.

Every work item records its attempts, source span when successful, discovered
references, audit references, completion time, last error code, and incomplete
reason. A process interruption leaves an `in_progress` checkpoint that is
converted to a bounded retry on resume. Retryable DeepSeek or HiSki failures do
not erase previously completed families or queued work. Terminal failures make
the session explicitly `incomplete` and explain why.

Checkpoint files are written atomically under local Application Support at
`Kalvian Roots/Traversal/sessions-v1.json`. They are resumable operational
state, not canonical evidence. Neither the canonical book nor FamilySearch is
modified.

## Verification

Run on 2026-08-20 with Xcode 27 beta 5:

- 52 core tests passed, including four Phase 8 coordinator tests;
- 13 MCP adapter tests passed;
- a four-family fixture graph stopped and resumed one family at a time;
- duplicate and cyclic references produced one work item per family;
- starting and resuming an already completed session were idempotent;
- a checkpoint survived construction of a new service and store instance;
- retryable HiSki failure preserved prior progress and later completed; and
- terminal malformed-AI output retained its exact incomplete reason.

The Phase 6 live HiSki/VPN smoke remains deferred at the user's request. Phase
8 failure handling is verified with deterministic stubs and makes no live
network call.
