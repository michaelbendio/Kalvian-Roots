# Kalvian Roots DSH/MCP Roadmap

## Status

This is the authoritative 11-phase roadmap for the DSH/MCP project. Phases are
numbered 0 through 10. The older `implementation-plan.md` documents the
application's historical source-comparison stages and is not this roadmap.

Work advances only when the current phase's test gate is satisfied or an exact
pre-existing blocker is recorded. Each slice remains bounded; later-phase work
is not pulled forward speculatively.

## Phase 0 — Contracts and baseline

**Deliverable:** Define service interfaces, MCP tool schemas, provenance model,
errors, cache behavior, credential ownership, audit behavior, and approval
boundaries. Record existing test status.

**Test gate:** Existing app tests still pass; the MCP architecture contract
answers every interface question.

**Status:** Complete. Contract work is recorded in `mcp-architecture.md` and
baseline status is recorded in `mcp-baseline.md`. Xcode 27 beta 5 runs the full
scheme: 452 tests pass, with no failures or skips. The four initially failing
stale expectations and their corrections are recorded in the baseline.

## Phase 1 — Book-access foundation

**Deliverable:** Isolate a Foundation-based Book Text Service that locates and
loads the canonical local Documents source, finds a family by identifier, and
returns the exact family block with source revision, page, and line provenance.
No AI or network access is involved.

**Test gate:** `SAKERI 4` and `PUUKANGAS 6` match saved exact-source fixtures;
missing, malformed, boundary-prefix, unavailable-file, wrong-marker, and
changed-source cases are tested; the canonical source hash is unchanged.

**Status:** Complete. `KalvianRootsCore` provides the read-only Book Text
Service and exact-source models. The existing app delegates validation and
family extraction to the same core. Sixteen core contract tests and three app
integration tests cover the gate; the complete app scheme passes 455 tests with
no failures or skips. Acceptance evidence is recorded in `mcp-phase1.md`.

## Phase 2 — First MCP vertical slice

**Deliverable:** Create the Swift MCP executable and expose only
`get_family_text`. Register it with DSH through a thin plugin or bundle.

**Test gate:** DSH requests `SAKERI 4`; the MCP result exactly matches the Book
Text Service result; discovery, startup, shutdown, standard-output discipline,
and structured errors work; no AI, HiSki, or FamilySearch access occurs.

## Phase 3 — Family Parsing Service

**Deliverable:** Move the existing DeepSeek-backed parser behind the shared
service boundary. Add `parse_family` and `get_parsed_family`, versioned schema
validation, validated cache behavior, saved JSON fixtures, and credential-provider
integration.

**Test gate:** Difficult saved families, multiple spouses, exact names and
patronymics, invalid JSON, unsupported schemas, and cache invalidation are
covered without live calls. A separate opt-in smoke test checks the current
DeepSeek prompt.

## Phase 4 — Family Network Service

**Deliverable:** Expose deterministic `as_child` and `as_parent` resolution,
person/couple matching, bounded traversal, cycle and missing-reference
detection, conflict reporting, and field-level provenance.

**Test gate:** Maria resolves from `SAKERI 4` to `PUUKANGAS 6`; her full marriage
and death claims retain their source family/page/span; the 3 March versus 13
March birth conflict remains visible; cycles terminate safely.

## Phase 5 — Juuret Citation Service

**Deliverable:** Expose deterministic Juuret citation generation for a selected
person, including arrow placement, harvested facts, all source spans, warnings,
and conflicts.

**Test gate:** Maria's citation matches approved copy and arrow placement;
multiple spouses, missing dates, conflicts, and the approved multi-page display
policy are covered; no AI or network calls occur.

## Phase 6 — HiSki research service

**Deliverable:** Expose deterministic birth, marriage, and death query
construction, saved-result parsing, explicit live searches, and detail-record
retrieval through the existing `sl.gif` logic.

**Test gate:** Query construction and saved HTML fixtures are covered; returned
names remain exact; ambiguous sets remain candidates; an opt-in live smoke test
succeeds under the explicit VPN-ready workflow.

## Phase 7 — Single-family DSH researcher

**Deliverable:** Teach DSH to coordinate the services for one family and return
a readable workup containing accessed families, parsed data, provenance,
conflicts, Juuret and HiSki proposals, and human decisions required.

**Test gate:** Complete one `SAKERI 4` to `PUUKANGAS 6` workup; no FamilySearch
or canonical-file mutation occurs; every proposed fact is traceable without
reading logs.

## Phase 8 — Bounded and resumable network traversal

**Deliverable:** Add a work queue, deduplication, cycle protection, checkpoints,
retry and rate limits, cost controls, and resumable audit records with explicit
network boundaries.

**Test gate:** A three-to-five-family fixture network stops and resumes without
duplication; repeated execution is idempotent; failed AI or HiSki calls do not
corrupt progress; incomplete families report why.

## Phase 9 — FamilySearch-assisted citation workflow

**Deliverable:** Present approved citation text and source links for copying or
visible UI-driven attachment. FamilySearch traversal remains Juuret-driven and
bounded; there is no unrestricted crawler or silent insertion.

**Test gate:** Under direct human supervision, one real person's citations are
approved individually and remain traceable to the saved workup; rejected and
deferred proposals retain their dispositions.

## Phase 10 — Juuret Project pilot

**Deliverable:** Process a small defined section of the book and measure parsing
accuracy, reference resolution, HiSki match quality, citation quality, review
time, AI cost, network failures, and unresolved conflict types.

**Test gate:** The pilot produces usable citations for the defined family set;
errors and conflicts are documented; the user decides whether broader traversal
is justified; packaging, installation, backup, update, and recovery procedures
are defined before scale-up.
