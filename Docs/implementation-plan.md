Kalvian Roots Implementation Plan
=================================

Purpose
-------

This document describes the incremental plan and current implementation status
for integrating:

1. FamilySearch family data
2. Juuret Kälviällä reconstructed families
3. HisKi parish christening records

The system will compare these sources and generate citation proposals.
All citations require explicit user approval before insertion.

The implementation is intentionally incremental. Each stage must work and be
testable before proceeding to the next. Older stage text should be read as a
planning record when the corresponding feature is already implemented.


Guiding Principles
------------------

1. Human in the loop

   The system never inserts citations automatically.
   It proposes actions and waits for approval.

2. Small deterministic steps

   Each stage produces visible output and tests.

3. Incremental development

   The system evolves as implementation proceeds.

4. Auditable workflow

   Every processed family produces a report showing:
   - FamilySearch children
   - Juuret children
   - HisKi children
   - differences
   - proposed citations

5. Preserve source fidelity

   Names and patronymics are preserved exactly as found in each source.
   No rewriting or normalization of source text is performed.

6. Storage resilience

   The roots file and cache are local durable data on this machine.
   The app must not depend on iCloud or temporary-directory fallback.


Core Data Structures
--------------------

Person (existing domain model)

    familySearchId
    name
    birthDate
    deathDate


Family

    father
    mother
    children[]


Cross-Source Comparison Structures
----------------------------------

PersonCandidate

Represents a person record from a specific source.

    name
    birthDate
    source
    familySearchId (optional)
    hiskiCitation (optional)

Sources

    .familySearch
    .juuretKalvialla
    .hiski

A PersonCandidate preserves the original spelling of the name exactly
as it appears in the source.


PersonIdentity

Represents the cross-source identity of a child.

Identity is defined as:

    canonicalName + birthDate

where canonicalName is derived using NameEquivalenceManager.

This prevents ambiguity when names repeat within a family.

Example

    Maria 1791
    Maria 1793

These must be treated as distinct individuals.


FamilyComparisonResult

Groups PersonCandidate records by PersonIdentity.

For each identity it records presence in:

    FamilySearch
    Juuret
    HisKi

This structure drives:

    comparison reports
    discrepancy detection
    citation proposal generation


Name Equivalence
----------------

Name equivalence is handled by NameEquivalenceManager.

Names are not rewritten.

Examples

    Liisa ↔ Elisabet
    Johan ↔ Juho
    Matti ↔ Matias

Example comparison

    HisKi: Elisabeta
    Juuret: Liisa
    FamilySearch: Liisa

These resolve to the same PersonIdentity.

Patronymics are preserved exactly as found in the source text.
Patronymics are not identity keys.


Source Conversion Rule
----------------------

All source data must be converted to PersonCandidate before comparison.

    FamilySearch → PersonCandidate
    Juuret → PersonCandidate
    HisKi → PersonCandidate

All comparison logic operates exclusively on:

    PersonCandidate
    PersonIdentity
    FamilyComparisonResult


Storage Rule
------------

JuuretKälviällä.roots is treated as:

    local Documents canonical file

The app must:

    load JuuretKälviällä.roots from local Documents when available
    allow explicit user file selection when auto-load fails
    preserve the canonical text unless the user approves edits

Family network caches are local durable app data:

    Application Support/Kalvian Roots/Cache/families.json

Do not reintroduce iCloud/ubiquity, CoreData, CloudKit, or temporary cache
fallback behavior without an explicit design change.


Stage 1 – Extract FamilySearch Family
-------------------------------------

Input

    FamilySearch person ID

Example

    K1K9-QMK

Process

    Open the FamilySearch person page and extract:
    - spouses
    - children

Do not expand recursively beyond the nuclear family.

Output

    fsChildren[] → converted to PersonCandidate

Notes

    FamilySearch traversal is bounded and Juuret-driven.
    Do not build a general FamilySearch crawler.


Stage 2 – Parse Juuret Family
-----------------------------

Input

    Juuret Kälviällä family text block

Extract

    birthDate
    childName
    couples
    couple marriage dates
    spouse-specific child groups

Output

    jkChildren[] → converted to PersonCandidate

Notes

    Multiple-spouse Juuret families are part of the current model.
    Children must remain grouped with the spouse/couple they belong to.
    Do not flatten children across spouses when generating Kalvian Roots
    citations.


Stage 3 – Build HisKi Family-Child Query
----------------------------------------

Goal

    Build HisKi queries that retrieve child sets for Juuret couples.

Search scope

    Use the configured Central Ostrobothnia parish set already defined
    in HiskiService, not a single parish.

Input

    father given name
    father patronymic
    mother given name
    mother patronymic
    marriage year

Query rules

    child first name = blank
    years start = marriage year - 1
    years end   = marriage year + 35

Named constants

    yearsBeforeMarriage = 1
    childbearingWindowYears = 35
    maxHiskiResults = 50

Populate the following HisKi parameters:

    etunimi       = ""
    alkuvuosi     = start year
    loppuvuosi    = end year
    ietunimi      = father given name
    aetunimi      = mother given name
    ipatronyymi   = father patronymic
    apatronyymi   = mother patronymic

Result

    HisKi family-child query URL


Stage 4 – Parse HisKi Family Query Results
------------------------------------------

From the HisKi family query result table extract, for each row:

    birthDate
    childName
    fatherName
    motherName
    detail record path from the sl.gif link (the magnifying-glass icon)

Purpose

    This parsed row data is used to build cross-source comparison data.

Output

    hiskiChildren[] → converted to PersonCandidate

Notes

    At this stage, the parsed row does not yet require the final citation URL.
    It only needs enough information for comparison plus the child detail link.

    Existing code already uses sl.gif href parsing for single-record queries.
    The family-query implementation should reuse that parsing approach rather
    than invent a different link extraction method.


Stage 5 – Harvest HisKi Citation URLs
-------------------------------------

For each parsed HisKi child row:

    follow the child detail page link from the sl.gif anchor
    extract the final citation URL

This step must reuse the existing citation extraction logic already
present in HiskiService.

The child detail page provides:

    stable event page
    event identifier
    final citation link

Output

    hiskiCitation attached to the corresponding PersonCandidate

Implementation note

    Existing code already knows how to extract the sl.gif href and how to
    derive the final citation URL from the child detail page.
    The family-query implementation should broaden the parser from
    one matching row to all matching rows and reuse the existing
    citation extraction logic.

Recommended refactor

    Extract shared sl.gif href parsing into a helper such as:

        extractSlGifLinks(from html: String) -> [String]

    Then reuse that helper for both:
        - single-record result matching
        - family-query result parsing


Stage 6 – Build Person Candidates
---------------------------------

Convert all sources into PersonCandidate:

    fsCandidates
    jkCandidates
    hiskiCandidates

No comparison occurs before this step.


Stage 7 – Build FamilyComparisonResult
--------------------------------------

Group all PersonCandidate records by PersonIdentity.

Compute:

    intersection(FS, JK)
    intersection(FS, HisKi)
    intersection(JK, HisKi)

and differences:

    FS-only
    JK-only
    HisKi-only

This identifies discrepancies and additional children.


Stage 8 – Prepare HisKi Citation Proposals
------------------------------------------

For each HisKi child that corresponds to a FamilySearch person:

    prepare citation proposal

Example

    Child: Matti
    Birth: 25 Jun 1802
    Citation: https://hiski.genealogia.fi/...

Notes

    The citation proposal uses the final citation URL harvested from
    the child detail page.


Stage 9 – Insert HisKi Citations (Manual Approval)
--------------------------------------------------

After approval:

    open
    /tree/person/sources/{personID}

    create source
    populate fields
    save

Verification

    confirm citation appears on the person page


Stage 10 – Prepare Kalvian Roots Citations
------------------------------------------

For children in:

    intersection(FS, JK)

Generate citation

    Huhtala, Uuno.
    Juuret Kälviällä II:264.
    Family of Elias Matinp. Tikkanen and Maria Antint. Passoja.

Present proposal to the user for approval.


Stage 11 – Update Canonical Juuret File
---------------------------------------

Add FamilySearch IDs to the canonical text.

Example

    ★ 25.06.1802 Matti <K1K9-QQW>


Testing Strategy
----------------

Each stage must include tests verifying:

    - data extraction
    - parsing
    - candidate construction
    - identity grouping
    - comparison results
    - citation generation

The system should fail early if a stage produces unexpected results.

Specific tests should cover:

    - repeated names within one family
    - HisKi-only children
    - FamilySearch-only children
    - Juuret-only children
    - name equivalence without source-name rewriting
    - family-query HisKi result parsing
    - sl.gif href extraction
    - citation URL harvesting from child detail pages
    - family-child query construction:
        • blank child first-name parameter
        • start year = marriage year - 1
        • end year = marriage year + 35
        • both parents’ given names and patronymics included
        • maxkpl = 50
        • configured Central Ostrobothnia parish set used


Future Enhancements
-------------------

    fallback HisKi queries
    improved name equivalence learning
    missing marriage date handling
    broader multiple-spouse HisKi query coverage
    multi-region support
    spouse expansion
    cache inspection and maintenance tools
    additional user-driven FamilySearch extraction affordances


Current Implemented Capabilities
--------------------------------

    DeepSeek-backed Juuret parsing
    multiple-spouse Juuret family parsing
    spouse-specific Kalvian Roots citation grouping
    local durable family network cache
    FamilySearch bookmarklet extraction workflow
    deterministic PersonCandidate → PersonIdentity comparison pipeline


Development Order
-----------------

1. Extract FamilySearch children
2. Parse Juuret families
3. Build HisKi family-child queries
4. Parse HisKi family query results
5. Harvest HisKi citation URLs
6. Convert all sources to PersonCandidate
7. Build FamilyComparisonResult
8. Generate HisKi citation proposals
9. Insert HisKi citations
10. Generate Kalvian Roots citations
