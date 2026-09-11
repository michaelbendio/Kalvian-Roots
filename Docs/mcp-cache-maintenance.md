# Scoped cache tools (MCP 1.1)

The `KalvianRootsMCP` 0.10.0 executable exposes 24 tools, including:

- `audit_family_cache`: source/parser status, embedded desktop family copies,
  and dependent research records for 1–10 explicit family IDs.
- `refresh_family_cache`: scoped staging, validation, backup, installation,
  dependency archival, and interrupted-update recovery.
- `preview_juuret_citation`: an existing selected-person citation rendered from
  native caches, without AI, context persistence, or review decisions.

The full contract is in [mcp-architecture.md](mcp-architecture.md#contract-11-amendment-scoped-cache-maintenance-and-citation-preview).
Request and response schemas are in [tool-catalog.json](../Schemas/mcp/v1/tool-catalog.json).

## Use

1. Read a family with `get_family_text` and retain its `source.sha256`.
2. Call `audit_family_cache` with `familyIds` and that hash as
   `expectedSourceSHA256`. `current` describes parser/provenance validation,
   not human acceptance of genealogical claims.
3. Call `refresh_family_cache` with the same scope/hash, `mode: "cached"`, and
   `dryRun: true` to inspect dependencies. A dry run does not predict new AI
   output and its changed-files list is empty because nothing was installed.
4. To apply, close the desktop app and use `dryRun: false`. `cached` installs
   current native records. Explicit `mode: "reparse"` instead invokes the
   existing parser once per requested family; a failure in any family prevents
   the staged set from being installed. AI attempts remain visible in failed
   operation audits too. Neither mode traverses to parse additional families.
5. Use `preview_juuret_citation` with an exact `PersonReference`, explicit
   traversal `limits`, and `expectedSourceSHA256`. Referenced families also need
   suitable native records. A missing cache or unresolved required `as_child`
   source is an explicit error. Returned contexts retain traversal warnings.

Example audit arguments after substituting the hash read in step 1:

```json
{
  "familyIds": ["TIKKANEN 2", "PIENI-PORKOLA 2", "PORKOLA 4", "HAUTAMÄKI 3"],
  "expectedSourceSHA256": "<current complete source SHA-256>"
}
```

Affected reviews, decisions, attachment histories, and other derived records
remain in the returned backup's `before/` files. They are withdrawn from active
stores because they need rebuilding and review against the refreshed data.
Unrelated records remain active. A refresh cannot approve a citation, modify
the canonical file, or write to FamilySearch.

The release executable is built with:

```sh
swift build --package-path KalvianRootsCore -c release
```

The existing local plugin launches
`KalvianRootsCore/.build/release/KalvianRootsMCP`. Restart the MCP host after
updating this executable so clients discover the additional tools and all
running hosts participate in cache locking.

## Verification on 2026-09-11

- Core and MCP protocol tests cover bounded scope, cache revisions, embedded
  replacement, removed links, preservation of unrelated data and human-history
  backups, failed multi-family staging, changed source/cache bytes, writer
  exclusion, recovery, desktop-open errors, and read-only citation behavior.
- The desktop `AIParsingServiceTests` and `CitationGeneratorTests` passed with
  Xcode 27 RC (18 and 35 tests respectively).
- The release executable was exercised through real stdio MCP. Live requests
  and successful responses validated against the committed JSON schemas.
- Audit and refresh dry run succeeded for the four corrected families. The
  cache contained 1,618 desktop network entries and 13 native records; these
  are cache counts, not a canonical-book family count.
- Preview returned editorial drafts for Tikkanen Simo and the two corrected
  Maria children. Both Hautamäki parent previews correctly required an
  unresolved `as_child` source. SAKERI 4 remained an ordinary book citation.
- All canonical/cache file hashes stayed unchanged, and the 13 live operations'
  audit records showed no external services contacted. No live apply or AI
  reparse was needed; installation was tested in isolated caches.

Saved live envelopes, rendered drafts, and hash/audit verification are under
`Documents/Kalvian Roots Research/Pieni-Porkola 2 - 2026-09-10/mcp-cache-tools-2026-09-11/`.
