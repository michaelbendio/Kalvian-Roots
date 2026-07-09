Kalvian Roots FamilySearch WebKit Extraction
===========================================

FamilySearch extraction is handled inside Kalvian Roots with a visible macOS
WebKit window. The app does not use a browser bookmarklet.

Behavior
--------

When the Juuret father has a FamilySearch ID, selecting the family in Kalvian
Roots opens the visible FamilySearch WebKit window and runs bounded extraction
for that current family. If FamilySearch requires sign-in or a security check,
the user handles it in the visible WebKit window and extraction continues from
the same current-family Details page.

After FamilySearch extraction finishes, Kalvian Roots publishes the
Juuret/FamilySearch comparison immediately so FS markers can appear beside
children before HisKi runs. It then pauses before starting HisKi network
queries. The navigation bar shows a green VPN-ready control just to the left of
the family ID field. The user turns on the VPN, clicks that control, and then
Kalvian Roots starts the HisKi family-span query and date-click cache warming
queries. When HisKi results return, H markers are added to the existing
comparison before slower citation/detail-page fetches continue.

When the Juuret father does not yet have a FamilySearch ID, selecting the
family opens FamilySearch in the visible WebKit window so the user can locate
the right FamilySearch Details page manually.

Upcoming-Family Preprocessing
-----------------------------

After a family is loaded, Kalvian Roots may preprocess the next two Juuret
Kälviällä families. This preprocessing is Juuret-driven and bounded to the
FamilySearch parent IDs already present in the upcoming Juuret family records.
It does not crawl recursively.

FamilySearch preprocessing waits a random 30-90 seconds before each uncached
extraction and stores successful results in the app's in-memory extraction
cache.

For date-click HisKi searches, preprocessing warms the same query cache used
when the user clicks dates in the UI. Adult birth/death dates and couple
marriage dates are warmed for every Juuret Kälviällä couple, including
additional spouses. For child birth dates, preprocessing builds the union of
Juuret Kälviällä children and FamilySearch children through the normal
comparison model before warming the child birth-date query cache. HisKi
family-span queries remain HisKi's own candidate pool, but they can use the
cached FamilySearch children to extend the query window for FamilySearch
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
