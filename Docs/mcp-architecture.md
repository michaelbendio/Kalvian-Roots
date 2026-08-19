# Kalvian Roots MCP Architecture and Contracts

## Status and authority

This document is the Phase 0 implementation contract for the Kalvian Roots
DSH/MCP project. It governs the MCP integration and takes precedence over older
conversational-tooling sketches. The existing application architecture remains
documented in `Architecture.md`; the older staged app plan remains in
`implementation-plan.md` as implementation history.

The roadmap for this work is `mcp-roadmap.md`. The recorded starting state is
`mcp-baseline.md`.

## Closed architectural decisions

| Question | Decision |
| --- | --- |
| Where does genealogy logic live? | In shared Swift services used by both the existing app and the MCP executable. DSH and the plugin contain no genealogy logic. |
| How is the engine shared? | Introduce a Foundation-based `KalvianRootsCore` Swift library boundary and move existing service implementations into it incrementally without changing their behavior. App-only UI, WebKit, and AppKit adapters remain in the app target. |
| How is MCP hosted? | One local Swift executable initially hosts all service adapters. Logical service boundaries do not require separate processes. |
| What transport is used? | MCP over standard input/output. Standard output is reserved for protocol messages; diagnostics go to standard error or the local audit log. |
| Where is the canonical book? | The local Documents file `JuuretKälviällä.roots`. A user-selected file may be read explicitly, but selecting it does not silently replace the local canonical file. |
| May MCP modify the book? | No tool in the initial MCP surface can modify it. A future write tool requires a separate contract amendment and explicit approval design. |
| May MCP modify FamilySearch? | No. FamilySearch remains visible, UI-driven, and bounded to the current family. MCP may return citation proposals and links only. |
| Where may AI be used? | Only inside the Family Parsing Service to interpret one exact Juuret family block. |
| How are people compared? | Sources first become `PersonCandidate`. Identity is exactly canonical name plus birth date. A missing birth date or a similar-looking name never proves identity. |
| How are conflicts handled? | Preserve every claim with provenance and return an explicit conflict. Never choose silently. |
| Who owns credentials? | The local Swift host owns them. DSH, MCP tool arguments, responses, plugin instructions, and audit records never contain secrets. |
| What is cached? | Derived parsed families, resolved networks, and research results, keyed by source and schema revisions. Exact book text remains authoritative and is not replaced by a cache. |

### FamilySearch progress annotations in the source

Angle-bracket values such as `<9DS5-XQ4>` are Juuret Project annotations, not
text printed in *Juuret Kälviällä*. They identify the person's FamilySearch
page and indicate that the person's source citations have been entered there.

The Book Text Service preserves these annotations byte-for-byte because they
are present in the canonical local source revision. Later parsing represents
them separately as `familySearchId` and reviewed-work status. They are not book
facts, are not rendered as Juuret evidence, and do not participate in person
identity matching. Duplicate or conflicting IDs are reported. Adding,
replacing, or removing an annotation requires explicit approval.

## Dependency and process boundaries

```text
DSH
  -> DSH plugin registration and workflow instructions
    -> KalvianRootsMCP executable (stdio MCP adapter)
      -> KalvianRootsCore service protocols and implementations
        -> local Documents source file
        -> local Application Support caches and audit records
        -> DeepSeek, only when parse_family is called
        -> HiSki, only for explicit HiSki research calls

Kalvian Roots macOS app
  -> the same KalvianRootsCore services
  -> app-only SwiftUI, AppKit, and visible WebKit adapters
```

The plugin registers and launches the server and gives DSH workflow guidance.
It must not parse family text, match people, construct HiSki queries, format
citations, or store credentials.

## Version ownership

Versions are independent so that one contract can change without invalidating
unrelated data:

| Version | Owner | Initial value | Changes when |
| --- | --- | --- | --- |
| MCP contract | KalvianRootsMCP | `1.0` | A tool name, request, response, or error contract changes. |
| Juuret family JSON schema | Family Parsing Service | `juuret-family/1` | Parsed family structure or validation rules change. |
| Provenance schema | KalvianRootsCore | `provenance/1` | Source or fact provenance structure changes. |
| Persistent cache schema | Owning cache service | Existing family cache remains `2`; new caches declare their own positive integer | On-disk representation changes. |
| Parser implementation | Family Parsing Service | immutable build identifier | Prompt, model selection, cleanup, or decoding behavior changes. |

Breaking MCP changes increment the major version. Additive optional fields may
increment the minor version. Responses always declare all applicable versions.
New native parsed-family cache output is valid only when its source hash,
family schema version, and parser implementation version all match. The
existing schema-2 `families.json` predates those fields and is handled through
the explicit legacy-import policy below rather than being silently treated as
a native cache hit.

The MCP catalog treats parsed family data as a schema-versioned object. The
machine-readable `juuret-family/1` content schema is committed in Phase 3, when
saved AI fixtures establish the validated contract; Phase 0 fixes its owner,
version identifier, and compatibility rules without inventing fields that the
parser has not yet been verified to produce.

## Common contract types

The following logical types are encoded as JSON objects in MCP responses.
Dates and historical names remain exact source strings unless a field is
explicitly labeled as a derived comparison value.

### SourceRevision

| Field | Type | Meaning |
| --- | --- | --- |
| `sourceId` | string | Stable local identifier for the configured roots source. |
| `fileName` | string | Must be `JuuretKälviällä.roots`. |
| `sha256` | string | SHA-256 of the complete UTF-8 file bytes. |
| `byteCount` | integer | Complete file size. |
| `loadedAt` | RFC 3339 string | When this revision was read. |
| `canonicalMarkerValid` | boolean | Whether the required first-line marker is present. |

Local absolute paths are operational details and are not returned by default.

### SourceSpan

| Field | Type | Meaning |
| --- | --- | --- |
| `sourceId` | string | Owning `SourceRevision`. |
| `sourceSha256` | string | Exact source revision. |
| `familyId` | string | Canonical family identifier. |
| `pageReferences` | string array | Page strings as read from the family header. |
| `startLine` | integer | One-based inclusive source line. |
| `endLine` | integer | One-based inclusive source line. |
| `blockSha256` | string | SHA-256 of the exact returned family block. |

Line numbers locate source evidence; they do not replace the exact raw block.

### FactClaim and FactConflict

A `FactClaim` contains:

- `claimId`: stable identifier within a workup;
- `subjectRef`: the selected person or couple in the structured family;
- `field`: for example `birthDate`, `deathDate`, or `marriageDate`;
- `value`: the exact source spelling or date string;
- `sourceSpan`: the family and page provenance;
- `sourceFieldPath`: the parsed JSON field that supplied the claim;
- `derivation`: `direct`, `aiParsed`, or `referenceHarvested`;
- `parserSchemaVersion` and `parserImplementationVersion` when AI participated;
- `warnings`: unresolved parsing or interpretation notes.

A `FactConflict` contains the field, subject, all competing `FactClaim` values,
and a machine-readable reason. It has no automatically selected winner.

### PersonReference

A person reference contains the exact source name, exact birth-date string when
present, role (`parent`, `child`, or `spouse`), family ID, couple index, and
person index. Patronymics and FamilySearch IDs may be carried as context, but
they are not identity keys.

### ToolEnvelope

Every successful tool response contains:

- `contractVersion` (`1.0`);
- `operationId` (UUID);
- `generatedAt` (RFC 3339 UTC);
- `tool`;
- `readOnly`;
- `data`;
- `warnings` (possibly empty);
- `conflicts` (possibly empty);
- `provenance` (possibly empty);
- `auditRef`.

Responses are complete rather than silently truncated. If a bounded operation
cannot return a complete result, it fails with `resource_limit_exceeded` and
reports the applicable limit.

## Swift service interfaces

These are behavioral interfaces. Phase 1 may refine Swift spelling to satisfy
concurrency and module boundaries, but may not change the behavior without
updating this contract first.

### Book Text Service

```swift
protocol BookTextServing: Sendable {
    func loadSource() async throws -> SourceRevision
    func getFamilyText(
        familyId: String,
        expectedSourceSHA256: String?
    ) async throws -> FamilyTextRecord
}
```

`FamilyTextRecord` contains the canonical family ID, exact raw block,
`SourceSpan`, and `SourceRevision`. Identifier lookup is case-insensitive after
trimming and collapsing whitespace, but the returned identifier and text retain
source spelling. A family header must match an identifier boundary, not merely
a string prefix.

The raw block begins at the family header and includes the original line ending
of its final content line. Separator-only blank lines and a trailing `#`
bookmark between families are outside the block. Interior blank lines, spelling,
tabs, punctuation, line endings, and angle-bracket FamilySearch annotations are
preserved exactly.

The service is read-only. It distinguishes malformed identifiers, identifiers
not in the source, missing source configuration, unreadable source, and a source
revision changed since the caller's expectation. It never invokes AI, network
services, or a cache.

### Family Parsing Service

```swift
protocol FamilyParsingServing: Sendable {
    func parseFamily(
        source: FamilyTextRecord,
        cachePolicy: ParseCachePolicy
    ) async throws -> ParsedFamilyRecord

    func getParsedFamily(
        familyId: String,
        sourceSHA256: String
    ) async throws -> ParsedFamilyRecord?
}
```

The service sends exactly one family block to DeepSeek, validates the versioned
JSON, decodes into the shared `Family` model, and preserves the raw block and
source span beside the parsed representation. It never rewrites source names.
Malformed output is rejected; there is no regex or reduced-data fallback.

### Family Network Service

```swift
protocol FamilyNetworkServing: Sendable {
    func resolveFamilyReferences(
        startingFamily: ParsedFamilyRecord,
        limits: TraversalLimits
    ) async throws -> FamilyNetworkResolution

    func resolvePersonContext(
        person: PersonReference,
        startingFamily: ParsedFamilyRecord,
        limits: TraversalLimits
    ) async throws -> PersonContextResolution
}
```

Resolution follows explicit `as_child` and `as_parent` references. It matches
people and couples using deterministic identity and relationship rules, detects
cycles and missing references, and returns harvested claims with field-level
provenance. Limits include maximum families, maximum depth, and maximum elapsed
time. Reaching a limit returns a partial, explicitly incomplete resolution; it
does not infer the remaining graph.

### Citation Service

```swift
protocol CitationServing: Sendable {
    func generateJuuretCitation(
        context: PersonContextResolution,
        selectedPerson: PersonReference
    ) throws -> CitationProposal
}
```

The citation generator is deterministic and makes no network or AI calls. A
proposal includes rendered text, the selected-person arrow target, every source
span used, conflicts, warnings, and `requiresApproval: true`. Conflicting facts
remain visible and are never silently resolved. The later display policy for
multiple page ranges may alter rendering, but all page provenance is already
required by this interface.

### HisKi Service

The existing `HiskiService` remains a separate specialized service. MCP-facing
adapters expose deterministic query construction, saved-HTML parsing, and
explicit live research. Detail links are extracted only through the anchor
containing `sl.gif`. A result is a candidate and never automatic proof of
identity.

### FamilySearch boundary

FamilySearch extraction remains in the visible macOS WebKit workflow described
by `familysearch-bookmarklet.md`. The MCP server does not crawl FamilySearch,
accept FamilySearch credentials, or attach citations. Comparison tools may use
previously extracted structured FamilySearch evidence supplied by the app.

## MCP tool contracts

All tools are read-only under contract version 1.0. `familyId` values use the
Book Text Service lookup rules. Optional `expectedSourceSHA256` fields provide
optimistic source-revision protection.

The machine-readable catalog is
`Schemas/mcp/v1/tool-catalog.json`. This section defines the semantics; the
catalog defines the registered request and response-data shapes. Both are
normative, and a change to either follows the version rules above.

| Tool | Introduced | Required input | Principal output | Network behavior |
| --- | --- | --- | --- | --- |
| `get_family_text` | Phase 2 | `familyId` | Exact text, pages, source revision, and source span | None |
| `parse_family` | Phase 3 | `familyId`; optional `expectedSourceSHA256`, `cachePolicy` | Validated parsed family, schema/parser versions, warnings, provenance | DeepSeek only on cache miss or explicit refresh |
| `get_parsed_family` | Phase 3 | `familyId`, `sourceSHA256` | Cached parsed record or `found: false` | None |
| `resolve_family_references` | Phase 4 | `familyId`, `TraversalLimits` | Bounded family graph, cycles, missing references, conflicts, provenance | DeepSeek only for uncached referenced families |
| `resolve_person_context` | Phase 4 | `familyId`, `PersonReference`, `TraversalLimits` | Selected-person claims, harvested facts, conflicts, provenance | Same as reference resolution |
| `generate_juuret_citation` | Phase 5 | resolved context ID, selected `PersonReference` | `CitationProposal` | None |
| `build_hiski_query` | Phase 6 | event type and motivating person/fact context | Query specification and URL | None |
| `search_hiski` | Phase 6 | query specification; explicit live-search flag | Candidate result rows and query provenance | HiSki only |
| `get_hiski_record` | Phase 6 | candidate record reference | Exact detail evidence and canonical `sl.gif`-derived link | HiSki only |
| `compare_family_sources` | Phase 7 | Juuret context plus structured FamilySearch/HiSki candidates | `FamilyComparisonResult` representation and discrepancies | None |
| `prepare_citation_proposals` | Phase 7 | comparison/workup ID and selected person | Juuret and HiSki proposals requiring approval | None |

### Request shapes

- `TraversalLimits`: `maxFamilies` (1–25), `maxDepth` (0–10), and
  `maxElapsedSeconds` (1–300).
- `cachePolicy`: `useValidated`, `refresh`, or `cacheOnly`.
- A `PersonReference` must identify one member in the supplied family. Names
  alone are not accepted as a unique selector.
- Live AI and HiSki calls are never implicit in tests and are distinguishable
  in the request and audit record.

### Result stability and bounds

Arrays have deterministic ordering: source file order for families and people,
event date then source order for HiSki candidates, and source order for
conflicts. Tool output must not depend on dictionary iteration order.

`get_family_text` returns a complete family block up to 64 KiB. Larger blocks
fail instead of truncating. Network tools default to one starting family and
must receive explicit traversal limits for expansion.

## Error contract

Transport/protocol failures use MCP errors. Expected genealogical ambiguity,
conflicts, missing references encountered during bounded traversal, and empty
research results are successful envelopes with structured warnings or
conflicts.

Every tool error has `code`, `message`, `operationId`, `retryable`, and optional
structured `details`. Codes are:

| Code | Meaning |
| --- | --- |
| `invalid_request` | Required input is missing or has the wrong shape. |
| `invalid_family_identifier` | Identifier syntax is malformed. |
| `source_not_configured` | No canonical or explicitly selected source is available. |
| `source_unreadable` | The source cannot be read or fails its canonical marker check. |
| `family_not_found` | A validly shaped identifier does not occur in this source revision. |
| `source_changed` | `expectedSourceSHA256` does not match the current source. |
| `schema_version_mismatch` | Persisted or returned structured data uses an unsupported schema. |
| `parser_not_configured` | The Family Parsing Service has no usable DeepSeek credential. |
| `malformed_ai_output` | AI output failed JSON or family-schema validation. |
| `external_service_unavailable` | DeepSeek or HiSki could not complete the request. |
| `authorization_required` | A visible, user-controlled sign-in or authorization step is needed. |
| `rate_limited` | An external service rejected the request for rate reasons. |
| `cache_unavailable` | A required durable cache could not be read or written. |
| `record_not_found` | A requested cached parse, workup, or research record is absent. |
| `resource_limit_exceeded` | A declared output or traversal limit would be exceeded. |
| `approval_required` | A requested operation is outside the read-only contract. |
| `unsupported_operation` | The requested behavior is not part of this contract version. |
| `internal_error` | An unexpected implementation failure; secrets and raw credentials are redacted. |

## Cache contract

- Book text is always read from the configured source and never served from a
  derived cache.
- The existing
  `Application Support/Kalvian Roots/Cache/families.json` file is the primary
  bootstrap source for already parsed families. It remains owned by the
  existing `FamilyNetworkCache` and `PersistentFamilyNetworkStore`; the MCP
  implementation must reuse those models and storage rather than create a
  competing reader or overwrite the file.
- A schema-2 legacy entry stores a decoded `FamilyNetwork`, cache timestamp,
  and extraction duration. It does not retain the raw DeepSeek response,
  source-file hash, family-block hash, prompt/parser version, or JSON schema
  identifier. Code and reports must not imply that those fields are known.
- Phase 3 may import a legacy entry into the new parsed-family cache after it
  decodes through the existing model, passes the current structural validator,
  identifies the requested main family, and is associated with the current
  exact Book Text Service block. The imported record records the legacy cache
  key and timestamp, the current source span used for association, an import
  timestamp, and a warning that the original source revision and parser build
  are unknown. Association with the current source is not evidence that the
  legacy parse was produced from that revision.
- A usable legacy hit avoids a live DeepSeek call. DeepSeek is used only when
  neither a matching native entry nor a usable legacy entry exists, or when the
  caller explicitly selects `refresh`. `cacheOnly` never invokes DeepSeek.
- Malformed, undecodable, or wrong-family legacy entries are reported and left
  untouched. Import must not delete, rewrite, or wholesale regenerate the
  existing cache. Page or source discrepancies become warnings or conflicts;
  they are not silently resolved.
- Parsed-family cache keys include source SHA-256, family ID, family schema
  version, and parser implementation version.
- Network-resolution cache keys additionally include resolution-policy version
  and traversal limits.
- HiSki evidence records retain the exact query, retrieval time, response hash,
  exact returned names, and canonical record reference.
- Cache records live under local Application Support and never in iCloud,
  temporary directories, CoreData, or CloudKit.
- A stale native cache is a miss, not a migration guess. The documented legacy
  import above is the only compatibility path for schema-2 family-network
  entries. Corrupt or inaccessible cache state is reported. The service does
  not silently continue with throwaway storage.
- Tests use saved source, JSON, and HTML fixtures. Live smoke tests are separate
  and opt-in.

## Credential contract

- The DeepSeek key belongs to the local Swift host and is stored as a generic
  password in the user's macOS Keychain under a Kalvian Roots service name.
- The app and MCP executable use a shared `CredentialProviding` adapter. Phase
  3 includes migration from any current app-local storage after user
  confirmation; Phase 0 does not move or expose the existing credential.
- No tool accepts a DeepSeek key, FamilySearch password, cookie, or browser
  session token.
- FamilySearch authentication remains inside the visible WebKit session.
- HiSki uses no stored account credential. VPN readiness remains an explicit
  user-controlled precondition for live HiSki calls.
- Secrets are redacted from errors, logs, audit records, fixtures, and tests.

## Approval and mutation boundaries

Contract version 1.0 exposes research and proposals only.

- Reading book text, cached structured data, and saved evidence needs no
  approval beyond the user's research request.
- Live DeepSeek or HiSki calls must be visible in the requested workflow and
  recorded in the audit entry.
- Every citation result is a proposal with `requiresApproval: true`.
- DSH must present discrepancies and proposal text, then wait for explicit user
  approval before any external attachment or canonical-text change.
- Approval of one proposal does not approve another person, citation, family,
  or source update.
- The server has no tool that attaches a citation to FamilySearch or edits the
  canonical roots file. Adding such a tool requires a versioned contract
  amendment, optimistic source-hash checking, a reviewed old/new preview, and a
  separately recorded approval event.

## Audit contract

Every operation receives a UUID and an append-only local audit entry under
Application Support. The entry records:

- timestamp, tool, contract version, and executable build;
- non-secret request parameters;
- source, block, fixture, and result hashes as applicable;
- cache hit/miss and external services contacted;
- warnings, conflicts, completion status, and error code;
- proposal IDs and later approval disposition when available.

Audit records are resumable research state, not canonical evidence. They never
contain credentials. Raw source text may be referenced by hash and span rather
than duplicated into every entry.

## Phase 0 acceptance checklist

- [x] Service ownership and Swift boundaries are defined.
- [x] MCP hosting, transport, tool inputs, outputs, versioning, and bounds are defined.
- [x] Machine-readable MCP request and response-data schemas are committed.
- [x] Provenance and conflict representation are defined.
- [x] Error semantics are defined.
- [x] Cache ownership and invalidation are defined.
- [x] Credential ownership is defined.
- [x] Human-approval and mutation boundaries are defined.
- [x] Audit behavior is defined.
- [x] The 0–10 roadmap is recorded separately.
- [x] The current non-Xcode baseline is recorded separately.
- [x] Existing Swift app tests pass on Xcode 27 beta 5 (452 pass, 0 fail,
  0 skipped).

Phase 0 is closed. The initial failures and their test-only corrections are
recorded so later work can distinguish the verified baseline from regressions.
