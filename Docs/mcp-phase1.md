# Kalvian Roots MCP Phase 1 Acceptance

## Outcome

Phase 1 is complete. The repository now has a Foundation-based shared Swift
library, `KalvianRootsCore`, containing a read-only Book Text Service. The
existing app links that library and uses the same source snapshot for canonical
marker validation and family extraction.

No MCP server, AI call, HiSki access, FamilySearch access, cache, or citation
behavior was added in this phase.

## Implemented boundary

The core provides:

- `BookTextServing` and `BookTextService`;
- `SourceRevision`, `SourceSpan`, and `FamilyTextRecord`;
- local Documents and explicit-selection source locators;
- injectable data reading and time for deterministic tests;
- SHA-256 source and family-block revisions;
- exact family-header indexing with normalized lookup and exact returned source
  spelling;
- structured errors matching the Phase 0 error codes; and
- a 64 KiB complete-block limit that rejects rather than truncates.

The app's `RootsFileManager` retains observable UI state and platform file
selection. It now delegates validation and exact extraction to
`BookTextSnapshot`. Explicitly selecting a source reads that file without
silently copying it over the local Documents source.

## Exact-text policy

A returned block starts at its family header and ends after the original line
ending of its final content line. Separator blank lines and a separator `#`
bookmark immediately before the next family are excluded. Content inside the
block is not reconstructed or normalized.

Tabs, Finnish spelling, punctuation, interior blank lines, LF or CRLF line
endings, and angle-bracket FamilySearch IDs remain exact. Angle-bracket IDs are
project progress annotations, not printed book evidence; Phase 1 preserves but
does not interpret them.

## Fixture and provenance gate

Saved fixtures contain exact copies of the current `PUUKANGAS 6` and `SAKERI 4`
blocks. The tests also compare those fixtures directly with the configured
local Documents source when it is available.

| Family | Pages | Source lines | Result |
| --- | --- | --- | --- |
| `PUUKANGAS 6` | `204` | 4,572–4,580 | Exact fixture match |
| `SAKERI 4` | `265`, `266` | 6,565–6,578 | Exact fixture match |

The contract suite covers:

- trimmed, collapsed-whitespace, and case-insensitive lookup;
- exact prefix boundaries (`SAKERI 4` versus `SAKERI 40`);
- letter suffix boundaries (`MIEKKOJA 1` versus `MIEKKOJA 1B`);
- malformed and missing identifiers;
- unavailable, unreadable, wrong-name, wrong-marker, and invalid-UTF-8 sources;
- duplicate family headers;
- expected-source revision mismatches;
- exact hashes, lines, pages, line endings, and interior blanks;
- preservation of angle-bracket FamilySearch annotations;
- oversized-block rejection; and
- no source mutation or implicit selected-file copy.

## Verification

Run on 2026-08-19 with Xcode 27 beta 5:

```sh
cd KalvianRootsCore
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" swift test
```

Result: **16 passed, 0 failed**.

The complete app suite was run without parallel test workers because existing
name-equivalence tests share a process-global `UserDefaults` key; a parallel
run exposed that pre-existing cross-process test race, while the affected test
passed when isolated. The deterministic full command was:

```sh
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild test \
  -project "Kalvian Roots.xcodeproj" \
  -scheme "Kalvian Roots" \
  -destination "platform=macOS,arch=arm64" \
  -parallel-testing-enabled NO
```

Result: **455 passed, 0 failed, 0 skipped**.

The canonical source remained unchanged:

`3accc9e3cca9d2940798c7ff78fdb635e52564a806876501079ae145e67dd486`

## Phase boundary

Phase 2 may now wrap `BookTextServing.getFamilyText` as the single
`get_family_text` MCP operation. Phase 1 intentionally does not include an MCP
executable, plugin registration, protocol transport, AI parsing, or network
research.
