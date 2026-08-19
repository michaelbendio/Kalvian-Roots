# Kalvian Roots MCP Phase 2 Acceptance

## Outcome

Phase 2 is complete. The repository now builds a local Swift MCP executable,
`KalvianRootsMCP`, which exposes only the read-only `get_family_text` tool over
standard input/output. The tool delegates directly to the Phase 1
`BookTextServing` boundary.

No family parser, DeepSeek call, family network resolver, HiSki access,
FamilySearch access, cache lookup, citation generator, or write operation is
linked into this executable.

## Swift MCP boundary

The Swift package now contains:

- the existing `KalvianRootsCore` library;
- a `KalvianRootsMCPServer` adapter library for protocol and audit behavior;
- the `KalvianRootsMCP` stdio executable; and
- a focused MCP adapter test target.

The executable uses the official MCP Swift SDK pinned to revision
`a0ae212ebf6eab5f754c3129608bc5557637e605`. The latest tagged `0.11.0`
release did not compile under Xcode 27 beta 5 because its unused Network
transport triggered a newer Swift concurrency diagnostic. The pinned official
revision contains that upstream correction and keeps the build reproducible.

Standard output is reserved for newline-delimited MCP messages. The executable
uses the SDK's no-op logger and writes a fatal startup message only to standard
error. Closing standard input terminates the receive loop and the executable
exits cleanly.

## Tool contract

Discovery returns exactly one tool:

`get_family_text`

Its inputs are `familyId` and the optional optimistic-concurrency field
`expectedSourceSHA256`. Unexpected keys and incorrect value types fail with
`invalid_request`. Book Text Service failures preserve their Phase 0 codes,
including `invalid_family_identifier`, `family_not_found`, `source_changed`,
and `resource_limit_exceeded`. A call to any future tool name currently fails
with `unsupported_operation`.

Successful calls return the complete Phase 0 `ToolEnvelope` both as structured
MCP content and as deterministic JSON text. Errors return `code`, `message`,
`operationId`, `retryable`, and applicable details. Tool annotations declare
the operation read-only, idempotent, non-destructive, and closed-world.

The response always uses the schema's NFC `JuuretKälviällä.roots` filename
literal even when the macOS filesystem presents the path in decomposed Unicode.
This changes metadata only; source bytes and returned family text are untouched.

## Audit behavior

Each call appends one JSON record to:

`Application Support/Kalvian Roots/Audit/mcp-operations.jsonl`

The record contains the operation and tool identifiers, non-secret request
fields, source and block hashes, result hash, completion or error status, and
external services contacted. Phase 2 records `cacheStatus: not_applicable` and
an empty external-services list. The tests verify append-only JSON Lines
behavior.

## Plugin registration

The plugin-creator workflow produced and validated the personal plugin source:

`/Users/michaelbendio/plugins/kalvian-roots`

The personal marketplace is:

`/Users/michaelbendio/.agents/plugins/marketplace.json`

The installed and enabled plugin is `kalvian-roots@personal`, version `0.1.0`.
Its `.mcp.json` launches the release executable at:

`/Users/michaelbendio/KRoots.dsh/KalvianRootsCore/.build/release/KalvianRootsMCP`

The plugin contains registration and display metadata only. It contains no
genealogy logic, workflow parser, credentials, or source data.

## Verification

Run on 2026-08-19 with Xcode 27 beta 5.

The Swift package test suite passed:

- 16 Book Text Service tests;
- 5 MCP adapter, discovery, error, exact-response, and audit tests;
- 21 total tests, 0 failures.

The complete macOS app scheme was also run with parallel test workers disabled,
using the same deterministic baseline command as Phase 1. Its 448 XCTest tests
and 7 Swift Testing tests passed: 455 total, 0 failures, 0 skips.

The compiled release executable was then driven as an independent MCP process.
The check performed initialization, tool discovery, `SAKERI 4` retrieval,
standard-input closure, and process shutdown. It established:

- discovery returned only `get_family_text`;
- the returned raw text exactly matched the saved `SAKERI 4` fixture;
- the canonical filename bytes matched the schema literal;
- every standard-output line was an MCP JSON message;
- standard error was empty; and
- shutdown completed with exit code zero.

Finally, a fresh ephemeral Codex client loaded the installed plugin, invoked
`get_family_text` with `familyId: SAKERI 4`, and returned:

- family ID: `SAKERI 4`;
- block SHA-256:
  `8be71191a28f21cf772a157c916e680355512ce6575eeadb76c386cf72f55b08`.

The server audit record reported no cache or external-service contact. The
canonical source SHA-256 remained:

`3accc9e3cca9d2940798c7ff78fdb635e52564a806876501079ae145e67dd486`

## Phase boundary

Phase 3 may add the Family Parsing Service and its two parsing tools. Phase 2
does not expose or call the existing DeepSeek-backed parser. Phase 3 must reuse
the accumulated schema-2 family cache under the documented legacy-import
policy rather than bulk-regenerating cached families.
