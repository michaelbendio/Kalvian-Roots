Kalvian Roots FamilySearch WebKit Extraction
===========================================

FamilySearch extraction is handled inside Kalvian Roots with a visible macOS
WebKit window. The app does not use a browser bookmarklet.

Behavior
--------

When the Juuret father has a FamilySearch ID, selecting the family in Kalvian
Roots does not automatically open FamilySearch or run extraction. The user must
explicitly open FamilySearch in the visible WebKit window and explicitly start
extraction.

When the Juuret father does not yet have a FamilySearch ID, selecting the
family does not automatically open FamilySearch. The family view keeps manual
"Open FamilySearch in Kalvian Roots" and "Extract in-app FamilySearch" buttons
available so the user can locate the right FamilySearch Details page manually
and then extract from the current page.

Upcoming-Family Preprocessing
-----------------------------

After a family is loaded, Kalvian Roots may preprocess the next two Juuret
Kälviällä families. This preprocessing is Juuret-driven and bounded to the
FamilySearch parent IDs already present in the upcoming Juuret family records.
It does not crawl recursively.

FamilySearch preprocessing waits a random 30-90 seconds before each uncached
extraction and stores successful results in the app's in-memory extraction
cache. HisKi preprocessing for that same upcoming family then uses the cached
FamilySearch children when extending the HisKi query window for FamilySearch
children that are not present in Juuret Kälviällä.

Extraction Scope
----------------

The extractor reads only the currently visible FamilySearch person Details page
and its visible Spouses and Children groups. It opens each child's quick-card in
the page UI to read Birth, Christening, Death, and Burial values, then closes the
quick-card before moving to the next child.

FamilySearch quick-cards are interactive page UI, not a public API. The
extractor uses normal browser events: hover/click to open each card, pointer
leave/outside click/Escape to close it, and no DOM deletion. Extraction remains
manual or app UI-driven and is bounded to the current nuclear family.

Implementation
--------------

`FamilySearchDOMService.makeFamilySearchExtractorScript()` builds the shared DOM
extractor. WebKit wraps that script with
`FamilySearchDOMService.makeWebKitExtractionScript(...)` and returns the
structured JSON payload directly to Swift through the
`kalvianRootsFamilySearchExtraction` message handler.

Do not add automated crawling, hidden recursive traversal, or FamilySearch API
assumptions without a new approved design.
