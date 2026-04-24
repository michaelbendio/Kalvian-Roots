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

Source of Truth
---------------

Do not maintain a second hand-written bookmarklet. The local app renders the
bookmarklet link from `FamilySearchDOMService.makeBookmarklet()` so the visible
install link and extractor implementation stay in sync.
