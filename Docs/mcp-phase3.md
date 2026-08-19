# Kalvian Roots MCP Phase 3 Acceptance

## Outcome

Phase 3 is complete. The Swift MCP executable now exposes three tools:

- `get_family_text`;
- `parse_family`; and
- `get_parsed_family`.

The existing macOS app and MCP executable use the same `Person`, `Couple`, and
`Family` models, JSON decoder, DeepSeek prompt, and HTTP client. The former app
model files are compatibility aliases, not parallel data models.

## Cache-first behavior

`parse_family` checks cache sources in this order unless an explicit refresh is
requested:

1. a native parsed record matching family ID, complete source SHA-256, family
   schema, and parser implementation;
2. the accumulated schema-2
   `Application Support/Kalvian Roots/Cache/families.json`; and
3. DeepSeek, only when no usable cache entry exists.

`cacheOnly` fails with `cache_miss` rather than making a network request.
`refresh` deliberately bypasses both cache tiers. `get_parsed_family` reads
only the native revision-matched cache and never contacts a network service.

The 72,907,328-byte schema-2 cache remains untouched and contains 1,618 family
entries. A usable legacy entry contributes its decoded `network.mainFamily`.
It is structurally validated against the current exact family block and then
copied into the separate `parsed-families-v1.json` cache. The returned record
includes `legacy_cache_provenance_limited`, because schema 2 did not store the
raw DeepSeek response, original source hash, prompt version, or parser version.
Malformed legacy entries fail visibly and are not replaced by an implicit AI
call.

## Versioned family contract

The family schema is `juuret-family/1`, committed at
`Schemas/juuret-family/v1/schema.json`. It represents the existing family
model: exact family ID and pages, one or more couples, exact parent and child
names, patronymics, dates, spouses, references, FamilySearch progress IDs,
notes, and note definitions.

The decoder rejects malformed JSON, an unsupported declared schema, mismatched
family IDs, mismatched pages, absent couples, and absent parent names. It does
not reject repeated child names: those are historically common and remain
distinguishable by birth date. Source spellings and patronymics are retained
exactly. Angle-bracket FamilySearch IDs remain separate progress annotations.

## Credential and approval boundary

The MCP host obtains the existing DeepSeek key locally from the Kalvian Roots
application preferences domain, with `DEEPSEEK_API_KEY` as a command-line smoke
test option. The key is never accepted as a tool argument, returned in a tool
response, or written to the audit log.

All Phase 3 tools remain read-only. They do not modify the canonical source,
contact HiSki or FamilySearch, generate citations, or approve any downstream
action.

## Verification

Run on 2026-08-19 with Xcode 27 beta 5.

The offline Swift package suite passed 30 tests: 24 core tests and 6 MCP adapter
tests. Coverage includes exact names and patronymics, multiple spouses, repeated
names, malformed JSON, unsupported schema, source-hash invalidation,
cache-only misses, schema-2 import, malformed legacy rejection, zero AI calls
on legacy hits, tool discovery, structured responses, and audit behavior.

The opt-in live smoke test was then enabled explicitly. DeepSeek parsed the
exact `SAKERI 4` block with the current prompt, and the result passed schema and
family validation in 7.347 seconds.

The full existing macOS app scheme passed with parallel workers disabled:

- 448 XCTest tests;
- 7 Swift Testing tests;
- 455 total tests;
- 0 failures and 0 skips.

An independent release MCP process initialized, discovered all three tools,
parsed `SAKERI 4`, wrote only protocol JSON to standard output, left standard
error empty, and exited cleanly. It returned `legacy-schema2-unknown` with the
required provenance warning.

A fresh Codex client then loaded the installed personal plugin and called
`parse_family` with `cachePolicy: cacheOnly`. The MCP audit recorded
`cacheStatus: validated_hit`, an empty `externalServicesContacted` array, and
the `legacy_cache_provenance_limited` warning.

The canonical source SHA-256 remained unchanged:

`3accc9e3cca9d2940798c7ff78fdb635e52564a806876501079ae145e67dd486`

## Phase boundary

Phase 4 may resolve explicit family references and add field-level provenance,
cycle detection, missing-reference reporting, and conflict reporting. Phase 3
returns one validated family only; it does not traverse or harvest facts from
related families.
