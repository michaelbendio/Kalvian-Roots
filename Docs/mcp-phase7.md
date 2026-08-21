# Kalvian Roots MCP Phase 7 Acceptance

## Outcome

Phase 7 adds a bounded single-family researcher around the existing genealogy
engine. The shared core now owns `PersonCandidate`, `PersonIdentity`, name
equivalence defaults, deterministic family comparison, and genealogy date
parsing; the app uses those same implementations rather than a parallel MCP
comparison path.

Two read-only MCP tools complete the slice:

- `compare_family_sources` loads a stored person context, converts optional
  UI-extracted FamilySearch children and stored HiSki birth evidence to the
  common comparison model, retains conflicts and provenance, and stores the
  deterministic comparison.
- `prepare_citation_proposals` combines that comparison with its stored person
  context, deterministic Juuret proposal, and exact HiSki evidence to return a
  standalone workup for human review.

Neither tool performs AI, HiSki, FamilySearch, or canonical-file writes.

## Evidence and approval boundary

The workup includes its starting and accessed families, validated parsed
families, field-level claims, conflicts, source comparison rows, exact HiSki
query and result evidence, canonical detail links, citation proposals, and a
readable report. Every citation proposal has `requiresApproval: true`. The
report ends by stating that no FamilySearch or canonical Juuret change was
performed.

Missing FamilySearch data, unparseable birth dates, ambiguous HiSki sets,
unretrieved detail records, and Juuret conflicts become explicit review
decisions. An absent requested evidence ID fails instead of being silently
ignored.

## Network contexts

HiSki and FamilySearch must not share the same VPN context. The deferred live
HiSki smoke may be run with the VPN after the user confirms that doing so will
not disrupt another application. FamilySearch must not be opened or extracted
while that VPN is active because FamilySearch may require defensive human
verification. Phase 7 comparison and proposal preparation use stored evidence
and therefore need neither network context.

## Verification

Run on 2026-08-20 with Xcode 27 beta 5:

- 48 core tests passed;
- 12 MCP adapter tests passed;
- the full existing app test scheme passed;
- the `SAKERI 4` to `PUUKANGAS 6` vertical-slice workup passed;
- comparison and proposal tools recorded no contacted external services; and
- the MCP tool catalog remained valid JSON.

The Phase 6 live HiSki smoke remains deferred at the user's request. It is not
required for deterministic Phase 7 comparison and proposal preparation.
