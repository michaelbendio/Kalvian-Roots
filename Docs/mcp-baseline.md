# Kalvian Roots MCP Phase 0 Baseline

## Snapshot

Recorded on 2026-08-19 in the isolated MCP worktree.

| Item | Value |
| --- | --- |
| Worktree | `/Users/michaelbendio/KRoots.dsh` |
| Branch | `feature/kalvian-roots-mcp` |
| Commit | `38a4abe6230b04f7532460d80b9f35eb130b3790` |
| Working tree before Phase 0 edits | Clean |
| Original checkout | `/Users/michaelbendio/Kalvian-Roots`, retained on `feature/juuret-project-workup-cli` at the same commit |
| macOS | 27.0 build 26A5416b, arm64 |
| Python | 3.12.10 |

## Canonical source snapshot

The configured local Documents source was inspected read-only.

| Item | Value |
| --- | --- |
| Path | `~/Documents/JuuretKälviällä.roots` |
| Size | 812,158 bytes |
| SHA-256 | `3accc9e3cca9d2940798c7ff78fdb635e52564a806876501079ae145e67dd486` |
| `SAKERI 4` header | Source line 6,565 |
| `PUUKANGAS 6` header | Source line 4,572 |

No Phase 0 operation modified this file. Its hash must be checked again after
any future book-access or source-update test.

An older iCloud-path copy also exists and has a different hash. It is not the
canonical MCP source. Legacy standalone helpers that still reference
`JKlocation.txt` must not be used as the Book Text Service implementation.

## Test results

### Passing checks

The following command passed 14 tests:

```sh
python3 -m unittest discover -s Tools/juuret-project/tests -v
```

The following command passed 6 tests:

```sh
python3 -m unittest -v test_search_spouse.py
```

`git diff --check` passed before documentation edits.

### Blocked Swift baseline

The application test command is:

```sh
xcodebuild test -project "Kalvian Roots.xcodeproj" -scheme "Kalvian Roots"
```

It could not start because this machine has no active Apple developer directory
and no Xcode application was found under `/Applications`. The exact diagnostic
begins:

```text
xcode-select: error: Unable to get active developer directory.
```

This is a machine/toolchain blocker, not a demonstrated Swift test failure. The
Phase 0 test gate remains open until the full existing scheme runs on a
configured Xcode installation. If that run exposes pre-existing failures, they
must be recorded exactly without broadening Phase 0 into unrelated cleanup.

## Existing implementation inventory

The checkout contains reusable implementations for:

- local Documents source access (`RootsFileManager`);
- DeepSeek parsing (`AIParsingService`, `DeepSeekService`);
- family reference resolution (`FamilyResolver`);
- durable network caching (`FamilyNetworkCache`, `PersistentFamilyNetworkStore`);
- deterministic citation formatting (`CitationGenerator`);
- HiSki querying and `sl.gif` record-link extraction (`HiskiService`);
- visible, bounded FamilySearch WebKit extraction (`FamilySearchDOMService`);
- shared comparison models (`PersonCandidate`, `PersonIdentity`, and
  `FamilyComparisonResult`).

These implementations are currently compiled into the app target rather than a
shared engine library. Phase 1 begins the Foundation-only boundary with the Book
Text Service; later phases move or adapt existing services rather than creating
parallel implementations.

## Baseline risks carried into implementation

These are recorded risks, not Phase 0 behavior changes:

1. Existing comparison code contains same-date near-name grouping and a
   missing-date name-only fallback. New MCP comparison work must enforce the
   contract's exact `canonicalName + birthDate` rule and must not expose those
   heuristics as proof of identity.
2. `RootsFileManager` currently copies a selected source into local Documents.
   The Book Text Service must be read-only and must not inherit that implicit
   overwrite behavior.
3. Existing `RootsFileManagerTests` do not load controlled fixtures and contain
   conditional assertions and empty error tests. Phase 1 requires fixture-based
   exact-source tests.
4. `JKlocation.txt` and `search_child.py` still point to the older iCloud copy.
   They are legacy standalone tooling, not an MCP source-of-truth path.
5. The project currently has app and app-test targets only; the shared core and
   MCP executable targets do not yet exist.

## Phase 0 gate

| Requirement | Status |
| --- | --- |
| Service and MCP contracts defined | Pass — `mcp-architecture.md` |
| Machine-readable tool schemas defined | Pass — `Schemas/mcp/v1/tool-catalog.json` |
| Provenance, errors, credentials, cache, audit, and approval defined | Pass — `mcp-architecture.md` |
| Eleven-phase roadmap recorded | Pass — `mcp-roadmap.md` |
| Existing non-Xcode test status recorded | Pass |
| Existing app tests still pass | Blocked — Xcode toolchain unavailable |

Phase 0 is therefore **documented but not yet closed**.
