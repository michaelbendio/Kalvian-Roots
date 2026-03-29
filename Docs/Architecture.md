Kalvian Roots Architecture
==========================

Overview
--------

Kalvian Roots is a genealogy comparison and citation system that integrates:

    1. FamilySearch families
    2. Juuret Kälviällä reconstructed families
    3. HisKi parish records

The system extracts, normalizes, compares, and presents evidence across
these sources and proposes citations for user approval.

The system is built around a deterministic comparison pipeline, with AI
used only where necessary to interpret complex historical text.


High-Level Flow
---------------

    Juuret (AI-assisted parsing)
    FamilySearch (deterministic extraction)
    HisKi (deterministic query + parsing)

            ↓

        PersonCandidate

            ↓

        PersonIdentity

            ↓

    FamilyComparisonResult

            ↓

    Citation Proposals (manual approval required)


Core Principles
---------------

1. Human in the loop

   No citations are inserted automatically.

2. Deterministic where possible

   All comparison, matching, and HisKi parsing are deterministic.

3. AI used only where necessary

   AI is used exclusively for interpreting Juuret Kälviällä family text.

4. Source fidelity

   Original names, patronymics, and data are preserved exactly.


Core Data Models
----------------

PersonCandidate

    Represents a person from any source in normalized form.

    Fields:

        name
        canonicalName
        birthDate
        deathDate (optional)
        source (FS | Juuret | HisKi)
        sourceMetadata


PersonIdentity

    Groups PersonCandidates that represent the same individual.

    Identity rule:

        canonicalName + birthDate

    Note:
        Patronymics are NOT used for identity matching.


FamilyComparisonResult

    Contains the comparison of children across sources.

    Fields:

        fsChildren[]
        jkChildren[]
        hiskiChildren[]

        matches
        fsOnly
        jkOnly
        hiskiOnly

        citationCandidates


Source Pipelines
----------------

1. Juuret Kälviällä (AI-assisted)

    Input:

        Raw family text block

    Process:

        AIParsingService converts text → structured Family/Person data

    Output:

        PersonCandidate[]


    AI Responsibilities:

        - Interpret irregular historical text
        - Extract names, dates, relationships
        - Preserve original spellings

    AI is NOT used outside this step.


2. FamilySearch (deterministic)

    Input:

        Person ID

    Process:

        Extract spouses and children from FamilySearch page

    Output:

        PersonCandidate[]


3. HisKi (deterministic)

    Query Construction:

        - Father given name + patronymic
        - Mother given name + patronymic
        - Birth year range:

            marriageYear - 1
            marriageYear + 35

        - Child name left blank
        - Parish set fixed (Central Ostrobothnia)


    Result Processing:

        1. Fetch results table
        2. Parse rows into PersonCandidate[]
        3. Identify record links via sl.gif icon
        4. Open each record page
        5. Extract citation URL


    Output:

        PersonCandidate[]
        citation URLs


Comparison Pipeline
-------------------

All sources are converted to PersonCandidate before comparison.

Matching is performed using:

    canonicalName + birthDate

The system computes:

    matches across sources
    missing children per source
    additional children from HisKi

This produces a FamilyComparisonResult.


Citation Workflow
-----------------

1. Build comparison result

2. Generate citation proposals:

    - HisKi citations (primary records)
    - Juuret citations (compiled source)

3. Present proposals to user

4. Wait for explicit approval

5. Insert citations into FamilySearch


Juuret Canonical File
---------------------

File:

    JuuretKälviällä.roots

Characteristics:

    - Canonical historical source
    - Not modified automatically

Permitted change:

    - Insertion of FamilySearch IDs (after approval)


Name Handling
-------------

Rules:

    - Preserve original names exactly
    - Do not rewrite names during parsing

Normalization:

    - Handled by NameEquivalenceManager

Examples:

    Liisa ↔ Elisabet
    Johan ↔ Juho
    Matts ↔ Matti


Patronymics
-----------

Examples:

    Matinp.  (Matinpoika)
    Antint.  (Antintytär)

Rules:

    - Not surnames
    - Not used for identity matching
    - Preserved exactly as written


HisKi Integration Details
-------------------------

Parishes:

    Fixed set covering Central Ostrobothnia

Query behavior:

    - Broad search (max results increased)
    - No child name constraint
    - Parent-based filtering

Record identification:

    - sl.gif icon indicates record link
    - Link leads to detailed event page

Citation extraction:

    - Extract URL containing "+t" parameter
    - This is the canonical HisKi citation


App Structure
-------------

App Coordinator:

    JuuretApp

    Owns:

        AIParsingService
        NameEquivalenceManager
        HiskiService
        FileManager

UI:

    SwiftUI views using @Environment(JuuretApp.self)

Services:

    AIParsingService
    HiskiService
    FamilyResolver (future comparison/navigation)

Utilities:

    DebugLogger
    FamilyIDs
    FileManager


File I/O
--------

Primary file:

    JuuretKälviällä.roots

Storage strategy:

    - Prefer iCloud canonical location
    - Fallback to local Documents copy
    - Maintain synchronized local cache


Testing Strategy
----------------

Each stage must be testable independently:

    - Juuret parsing (AI output validation)
    - HisKi query construction
    - HisKi result parsing
    - comparison correctness
    - citation generation

Tests live in:

    KalvianRootsTests


Future Enhancements
-------------------

    - Multiple spouse handling in HisKi queries
    - Missing marriage date fallback
    - Improved name normalization
    - Automated FamilySearch navigation
    - Cached family networks
    - Multi-parish support (if needed)


Summary
-------

Kalvian Roots is a hybrid system:

    AI-assisted for interpreting complex historical text (Juuret)

    Deterministic for:

        - HisKi querying and parsing
        - FamilySearch extraction
        - cross-source comparison
        - citation generation

All actions remain user-controlled and auditable.

