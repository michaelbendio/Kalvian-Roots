Kalvian Roots Implementation Plan
=================================

Purpose
-------

This document describes the incremental plan for integrating:

1. FamilySearch family data
2. Juuret Kälviällä reconstructed families
3. HisKi parish christening records

The system will compare these sources and generate citation proposals.
All citations will require explicit user approval before insertion.

The implementation is intentionally incremental. Each step must work
and be testable before proceeding to the next.


Guiding Principles
------------------

1. Human in the loop

   The system never inserts citations automatically.
   It proposes actions and waits for approval.

2. Small deterministic steps

   Each stage produces visible output and tests.

3. Incremental development

   The system is expected to evolve as implementation proceeds.

4. Auditable workflow

   Every processed family should produce a report showing:
   - FS children
   - Juuret children
   - HisKi children
   - differences
   - proposed citations


Core Data Structures
--------------------

Person

    fsId
    name
    birthDate
    deathDate


Family

    father
    mother
    children[]


HisKiEvent

    birthDate
    childName
    fatherName
    motherName
    hiskiCitation   (URL to HisKi detailed record)


FamilyComparison

    fsChildren[]
    jkChildren[]
    hiskiChildren[]


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

    fsChildren[]


Stage 2 – Parse Juuret Family
-----------------------------

Input

    Juuret Kälviällä family text block.

Extract

    birthDate
    childName

Output

    jkChildren[]


Stage 3 – Construct HisKi Query
-------------------------------

Using parent information:

    fatherFirstName
    fatherPatronymic
    motherFirstName
    motherPatronymic
    marriageYear

Generate a HisKi query URL covering:

    marriageYear - 1
    marriageYear + 35


Stage 4 – Parse HisKi Results
-----------------------------

From the HisKi results table extract:

    birthDate
    childName
    fatherName
    motherName
    hiskiCitation

The hiskiCitation is the URL behind the magnifying-glass icon.


Stage 5 – Normalize Names
-------------------------

Apply simple normalization to make comparisons possible.

Examples

    Matts → Matti
    Johannes → Juho
    Brita → Briita
    Maria Elis → Maija Liisa


Stage 6 – Compare the Three Sources
-----------------------------------

Construct sets:

    FS children
    JK children
    HisKi children

Compute

    intersection(FS, JK)
    intersection(FS, HisKi)
    intersection(JK, HisKi)

and differences

    FS-only
    JK-only
    HisKi-only

This identifies discrepancies and additional children.


Stage 7 – Prepare HisKi Citation Proposals
------------------------------------------

For each HisKi child that corresponds to a FamilySearch person:

    prepare citation proposal

Example output

    Child: Matti
    Birth: 25 Jun 1802
    Citation: https://hiski.genealogia.fi/...


Stage 8 – Insert HisKi Citations (Manual Approval)
--------------------------------------------------

After approval:

    open
    /tree/person/sources/{personID}

    create source
    populate fields
    save

Verification:

    confirm citation appears on the person page.


Stage 9 – Prepare Kalvian Roots Citations
-----------------------------------------

For children in:

    intersection(FS, JK)

Generate citation

    Huhtala, Uuno.
    Juuret Kälviällä II:264.
    Family of Elias Matinp. Tikkanen and Maria Antint. Passoja.

Present proposal to the user for approval.


Stage 10 – Update Canonical Juuret File
---------------------------------------

Add FamilySearch IDs to the canonical text.

Example

    ★ 25.06.1802 Matti <K1K9-QQW>


Testing Strategy
----------------

Each stage must include tests verifying:

    - data extraction
    - parsing
    - comparison results
    - citation generation
    - citation insertion

The system should fail early if a stage produces unexpected results.


Future Enhancements
-------------------

The following improvements will be implemented later:

    fallback HisKi queries
    better name normalization
    multi-parish support
    spouse expansion
    caching of previously visited families
    automated traversal of FamilySearch families


Development Order
-----------------

1. Extract FamilySearch children
2. Parse Juuret families
3. Generate HisKi queries
4. Parse HisKi results
5. Compare children sets
6. Generate HisKi citation proposals
7. Insert HisKi citations
8. Generate Kalvian Roots citations
