Kalvian Roots — AGENTS.md
=========================

Purpose
-------

This repository implements the Kalvian Roots genealogy comparison system.

The system compares three historical sources:

    1. FamilySearch families
    2. Juuret Kälviällä reconstructed families
    3. HisKi parish christening records

The goal is to identify matching children across sources and propose
citations for FamilySearch and Kalvian Roots.

Agents working in this repository must follow the architecture and
workflow described in:

    Docs/implementation-plan.md


Architecture Overview
---------------------

All sources must be converted into a common comparison model.

Source records are converted to:

    PersonCandidate

Comparison is performed using:

    PersonIdentity
    FamilyComparisonResult

Agents must not compare raw source objects directly.


Identity Rules (Critical)
-------------------------

Children are identified by:

    canonicalName + birthDate

Do NOT match children by name alone.

Example:

    Maria 1791
    Maria 1793

These represent different individuals.

Repeated names within a family are common in Finnish parish records.


Name Handling Rules
-------------------

Source spellings must be preserved exactly.

Examples:

    HisKi: Elisabeta
    Juuret: Liisa
    FamilySearch: Liisa

Names must never be rewritten during parsing.

Name equivalence is handled by:

    NameEquivalenceManager

Example equivalences:

    Liisa ↔ Elisabet
    Johan ↔ Juho
    Matti ↔ Matias


Finnish Patronymic Names
------------------------

Many historical Finnish names use patronymics.

Examples:

    Matinp.  = Matinpoika   (son of Matti)
    Antint.  = Antintytär   (daughter of Antti)
    Kustaanp. = Kustaanpoika

Important rules:

1. Patronymics are not surnames.

   They identify the father’s name and change each generation.

2. Patronymics should not be treated as family surnames.

3. Patronymics should not be rewritten automatically.

4. Patronymics should not be used for identity matching.

Identity comparison must rely only on:

    canonicalName + birthDate

Example:

    Juho Matinp. (Juho, son of Matti)

The patronymic provides genealogical context but is not part of the
identity key.

Agents must preserve patronymics exactly as they appear in the source
text.


Source Conversion Rule
----------------------

All source data must first be converted to PersonCandidate.

    FamilySearch → PersonCandidate
    Juuret → PersonCandidate
    HisKi → PersonCandidate

Comparison operates only on:

    PersonCandidate
    PersonIdentity
    FamilyComparisonResult


Citation Workflow
-----------------

The system never inserts citations automatically.

All citations require explicit user approval.

The workflow is:

    1. Extract source data
    2. Convert to PersonCandidate
    3. Build FamilyComparisonResult
    4. Propose citations
    5. Wait for user approval
    6. Insert citation


Juuret Canonical Text
---------------------

The Juuret source text is canonical historical data.

Agents must not modify this text automatically.

FamilySearch IDs may be inserted into the canonical text only
after explicit confirmation by the user.


Testing
-------

All new comparison logic must include tests.

Tests live in:

    KalvianRootsTests

Tests should verify:

    - source parsing
    - comparison results
    - identity grouping
    - citation generation


Coding Guidelines
-----------------

Prefer deterministic logic over heuristics.

Avoid hidden name rewriting.

Preserve original historical data wherever possible.

Keep comparison logic separate from parsing logic.


Directory Structure
-------------------

Kalvian-Roots
    AGENTS.md
    README.md
    Docs/
        implementation-plan.md

    Kalvian Roots/
        Models/
        App/
        Services/

    KalvianRootsTests/


Agent Expectations
------------------

Agents modifying this repository should:

    • read Docs/implementation-plan.md before making architectural changes
    • maintain the PersonCandidate → PersonIdentity → comparison pipeline
    • avoid introducing new identity heuristics
    • add tests when modifying comparison logic

If uncertain about genealogy assumptions, prefer asking for
human confirmation rather than introducing automated behavior.

