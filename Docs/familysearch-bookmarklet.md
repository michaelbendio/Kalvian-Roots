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
`window.location.pathname`, opens each child detail flyout/panel from the parent
Details page, extracts visible Birth, Christening, Death, and Burial values, and
posts the result to:

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
3. For each child, try to open the visible FamilySearch quick-card and read the
   vital facts from that panel.
4. If the quick-card path cannot produce useful vital dates, fetch the child's
   details HTML and parse the same facts from that document.
5. If both detail paths fail, keep the summary data already visible on the
   parent page so the comparison still has a partial child record.
6. Post the extraction result to the local Kalvian Roots server.
7. Show a short success message on the FamilySearch page.

FamilySearch quick-cards are interactive page UI, not a public API. The
bookmarklet therefore uses normal browser events: hover/click to open the card,
pointer leave/outside click/Escape to close it, and no DOM deletion. That keeps
the extractor manual and low-impact while still letting it read the information
visible to the user.

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
