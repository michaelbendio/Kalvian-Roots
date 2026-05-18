Kalvian Roots FamilySearch Bookmarklet
=====================================

This is the generic Atlas bookmarklet workflow for FamilySearch extraction.

The bookmarklet is reusable for every Kalvian Roots family. It does not contain
a FamilySearch person ID. It reads the current ID from the active FamilySearch
Details page URL:

    https://www.familysearch.org/en/tree/person/details/<FamilySearchID>

Install
-------

1. Open a local Kalvian Roots family page.
2. Drag the "Kalvian Roots FamilySearch Extractor" link to the Atlas bookmarks
   bar, or click "Copy bookmarklet" and paste it into a new Atlas bookmark URL.
3. Reuse that same bookmark for every family.

Run
---

1. Open the FamilySearch person Details page for the parent shown in Kalvian
   Roots.
2. Click the "Kalvian Roots FamilySearch Extractor" bookmarklet in Atlas.
3. Return to the local Kalvian Roots family page to view comparison results.

Behavior
--------

The generated bookmarklet is produced by:

    FamilySearchDOMService.makeBookmarklet()

It runs in the FamilySearch page context, verifies that the current path matches
`/tree/person/details/<FamilySearchID>`, extracts the current ID from
`window.location.pathname`, reads each child's Details page without navigating
the active tab, extracts Birth, Christening, Death, and Burial values where
available, and posts the result to:

    http://127.0.0.1:8081/familysearch/extraction-result

If the bookmarklet is run from the wrong page, it alerts:

    Open a FamilySearch person Details page before running the Kalvian Roots extractor.

Code Walkthrough
----------------

The Atlas bookmark stores a `javascript:` URL. The code inside that URL is
generated from the Swift source in `FamilySearchDOMService`.

There are two layers:

1. `makeAtlasExtractorScript()` builds the real extractor. It defines helper
   functions, reads the FamilySearch Details page, creates structured child
   records, and posts JSON back to Kalvian Roots.
2. `makeBookmarklet()` wraps that extractor in a tiny launcher. The launcher
   reads the current FamilySearch person ID from the browser URL and calls
   `window.extractFamilySearchChildren(...)`.

The extractor works in this order:

1. Confirm the active page is a FamilySearch person Details page.
2. Read the focus person and spouse/child groups from the visible page.
3. For each child, first fetch the child's Details HTML and parse any vital
   facts available in that response.
4. If the static HTML does not contain usable vital facts, load the child
   Details page in a hidden frame and parse the rendered Birth, Christening,
   Death, and Burial values from that document.
5. If both detail paths fail, keep the summary data already visible on the
   parent page as partial context only. The parent summary usually exposes
   year-only life spans, so those values are not treated as exact Birth or
   Death dates.
6. Post the extraction result to the local Kalvian Roots server.
7. Show a short success message on the FamilySearch page.

FamilySearch quick-cards are interactive page UI, not a public API. The
bookmarklet no longer opens them during the normal extraction path or fallback.
Keeping extraction on Details pages and partial summary context avoids leaving
interactive FamilySearch UI running in the active tab.

Source of Truth
---------------

Do not maintain a second hand-written bookmarklet. The local app renders the
bookmarklet link from `FamilySearchDOMService.makeBookmarklet()` so the visible
install link and extractor implementation stay in sync.


Related Documents
-----------------

Before changing this workflow, also read:

    AGENTS.md
    Docs/Architecture.md
    Docs/implementation-plan.md

FamilySearch extraction must remain manual or user-triggered. Do not add
automated crawling or hidden repeated page navigation.
