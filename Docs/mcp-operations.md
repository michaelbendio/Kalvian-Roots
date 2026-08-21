# Kalvian Roots MCP Operations

## Data ownership

`JuuretKälviällä.roots` in the user's local Documents directory is the
canonical historical source. It is never regenerated, normalized, or changed
by the MCP workflow. FamilySearch identifiers in angle brackets are workflow
markers, not book text, and may be added only after explicit user approval.

Derived local state is stored below `Application Support/Kalvian Roots`:

- `Cache` contains the existing family cache and source-aware parsed-family
  cache;
- `Research` contains resolved contexts, comparisons, HiSki evidence, and
  citation reviews;
- `Traversal` contains resumable family-network sessions;
- `Pilot` contains versioned pilot reports; and
- `Audit` contains append-only MCP operation records.

Cache failure is a hard error. The system does not silently switch to temporary
or cloud storage.

## Installation

Build the `KalvianRootsMCP` release executable with the configured Xcode beta.
The personal `kalvian-roots` plugin registers that executable with Codex and
supplies the single-family research instructions. After installing or updating
the plugin, start a new Codex task so it discovers the current tool surface.

Credentials remain outside the repository. DeepSeek uses the existing local
credential provider. FamilySearch uses only the user's visible signed-in
browser session. No FamilySearch API credential is owned by the MCP server.

## Backup

Stop the app and MCP server before making a consistent backup. Back up both:

1. the canonical Documents copy of `JuuretKälviällä.roots`; and
2. the complete local `Application Support/Kalvian Roots` directory.

Keep the source file and derived-state backup from the same point in time.
Store backups in a location chosen by the user; derived caches must not be
silently moved to iCloud by the application.

## Update

Before updating, make a backup and record the current source SHA-256. Build and
run all core, MCP, and app tests. Validate the MCP catalog, rebuild the release
executable, update the plugin cachebuster, validate the plugin, and reinstall
it. Start a new Codex task before testing discovery.

Do not discard the existing DeepSeek family cache during an update. New cache
contracts import usable legacy entries and disclose their limited provenance.

## Restore and verification

With the app and server stopped, restore the canonical source and Application
Support directory together. Then verify that:

- the canonical filename and source SHA-256 match the backup record;
- saved JSON stores decode without schema or corruption errors;
- `get_family_text` returns an exact known family block; and
- a saved traversal, citation review, and pilot report can be retrieved.

Do not accept a restore merely because files exist; verify their content.

## Recovery from damaged derived state

Never repair damage by editing the canonical source automatically. Preserve a
copy of the damaged derived-state directory for diagnosis. Prefer restoring the
latest verified backup. If no usable backup exists, rebuild only derived state
from the unchanged canonical source and retained validated JSON fixtures or
family cache. Any facts that require new AI or network calls must be reported
and processed through the normal bounded workflow.

If the canonical source itself is damaged, stop and obtain human direction.
Do not overwrite it from derived JSON.

## External-service safety

Live HiSki use is opt-in. On 2026-08-20 its first VPN-backed smoke attempt timed
out, while the retry succeeded in 0.529 seconds; treat transient availability as
a retryable condition without discarding saved progress. Before a workflow uses
both HiSki and FamilySearch, disconnect the VPN before opening or operating
FamilySearch; FamilySearch may challenge VPN traffic. FamilySearch
actions remain visible, manual or UI-driven, Juuret-bounded, and individually
approved. The MCP server records reported outcomes but never silently attaches
a citation.
