//
//  HTMLRenderer.swift
//  Kalvian Roots
//
//  Server-side HTML rendering for family display
//

#if os(macOS)
import Foundation

/**
 * HTML Renderer for server-rendered family pages
 */
struct HTMLRenderer {

    // MARK: - Landing Page

    static func renderLandingPage(error: String? = nil, requestHost: String? = nil) -> String {
        let host = requestHost?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayHost = host?.isEmpty == false ? host! : "127.0.0.1:8081"
        let baseURL = "http://\(displayHost)"
        let accessMode = isLocalHost(displayHost) ? "local Mac browser" : "remote browser"
        let sampleWorkupURL = "\(baseURL)/family/SAKERI%201/workup"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Kalvian Roots</title>
            <style>
                \(cssStyles)
                .landing-container {
                    max-width: 760px;
                    margin: 100px auto;
                    padding: 40px;
                    background: white;
                    border-radius: 8px;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                }
                h1 {
                    color: #333;
                    margin-bottom: 30px;
                }
                .form-group {
                    margin-bottom: 20px;
                }
                label {
                    display: block;
                    margin-bottom: 8px;
                    color: #666;
                    font-weight: 500;
                }
                input[type="text"] {
                    width: 100%;
                    padding: 12px;
                    border: 2px solid #ddd;
                    border-radius: 4px;
                    font-size: 16px;
                    font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
                }
                input[type="text"]:focus {
                    outline: none;
                    border-color: #0066cc;
                }
                button {
                    background: #0066cc;
                    color: white;
                    border: none;
                    padding: 12px 30px;
                    border-radius: 4px;
                    font-size: 16px;
                    cursor: pointer;
                    font-weight: 500;
                }
                button:hover {
                    background: #0052a3;
                }
                .button-row {
                    display: flex;
                    gap: 10px;
                    flex-wrap: wrap;
                }
                .error-message {
                    color: #dc3545;
                    margin-top: 10px;
                    padding: 10px;
                    background: #fee;
                    border-radius: 4px;
                }
                .remote-panel {
                    margin-top: 28px;
                    padding-top: 22px;
                    border-top: 1px solid #e5e5e5;
                }
                .remote-panel h2 {
                    font-size: 18px;
                    margin: 0 0 12px 0;
                }
                .remote-grid {
                    display: grid;
                    grid-template-columns: minmax(130px, auto) 1fr;
                    gap: 8px 14px;
                    align-items: baseline;
                }
                .remote-label {
                    color: #666;
                    font-size: 13px;
                }
                .remote-value {
                    overflow-wrap: anywhere;
                }
                .remote-note {
                    margin-top: 14px;
                    color: #666;
                    font-size: 13px;
                }
            </style>
        </head>
        <body>
            <div class="landing-container">
                <h1>Kalvian Roots Browser</h1>
                <form method="GET" action="/family" id="familyForm" onsubmit="return openFamily(event)">
                    <div class="form-group">
                        <label for="family">Enter Family ID:</label>
                        <input type="text" id="family" name="id"
                               placeholder="e.g., KORPI 6"
                               required autofocus
                               oninput="updateWorkupPreview()">
                        \(error == "invalid" ? """
                        <div class="error-message">
                            Invalid family ID. Please check and try again.
                        </div>
                        """ : "")
                    </div>
                    <div class="button-row">
                        <button type="submit">Open Family</button>
                        <button type="button" onclick="openWorkup()">Open Workup</button>
                    </div>
                </form>
                <div class="remote-panel">
                    <h2>Server / Remote Access</h2>
                    <div class="remote-grid">
                        <div class="remote-label">Status</div>
                        <div class="remote-value">Kalvian Roots server is running on port 8081.</div>
                        <div class="remote-label">This browser</div>
                        <div class="remote-value">\(escapeHTML(accessMode))</div>
                        <div class="remote-label">Current URL</div>
                        <div class="remote-value"><code>\(escapeHTML(baseURL))</code></div>
                        <div class="remote-label">Workup URL</div>
                        <div class="remote-value"><code id="workupPreview">\(escapeHTML(sampleWorkupURL))</code></div>
                    </div>
                    <p class="remote-note">
                        From Tailscale, use this Mac's Tailscale name or 100.x address with port 8081.
                        FamilySearch WebKit extraction opens on the Mac running Kalvian Roots.
                    </p>
                </div>
            </div>
            <script>
                function canonicalFamilyId() {
                    const input = document.getElementById('family');
                    return input.value.trim().toUpperCase();
                }
                function workupURLFor(value) {
                    const familyId = value || 'SAKERI 1';
                    return '/family/' + encodeURIComponent(familyId).replace(/%20/g, '%20') + '/workup';
                }
                function familyURLFor(value) {
                    return '/family/' + encodeURIComponent(value).replace(/%20/g, '%20') + '?reload=1';
                }
                function updateWorkupPreview() {
                    const preview = document.getElementById('workupPreview');
                    preview.textContent = window.location.origin + workupURLFor(canonicalFamilyId());
                }
                function openFamily(event) {
                    if (event) {
                        event.preventDefault();
                    }
                    const familyId = canonicalFamilyId();
                    if (!familyId) {
                        document.getElementById('family').focus();
                        return false;
                    }
                    window.location.href = familyURLFor(familyId);
                    return false;
                }
                function openWorkup() {
                    const familyId = canonicalFamilyId();
                    if (!familyId) {
                        document.getElementById('family').focus();
                        return;
                    }
                    window.location.href = workupURLFor(familyId);
                }
                updateWorkupPreview();
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Family Display

    static func renderFamily(
        family: Family,
        network: FamilyNetwork?,
        homeId: String? = nil,
        citationText: String? = nil,
        sourceText: String? = nil,
        errorMessage: String? = nil,
        comparisonResult: FamilyComparisonResult? = nil,
        comparisonGroups: [FamilyChildrenComparisonGroup] = [],
        familySearchExtraction: FamilySearchFamilyExtraction? = nil,
        familySearchPersonId: String? = nil,
        workup: FamilyWorkup? = nil,
        hiskiChildSearchRequestsByCouple: [Int: HiskiService.FamilyBirthSearchRequest] = [:]
    ) -> String {
        // Determine home and displayed IDs
        let displayedId = family.familyId
        let actualHomeId = homeId ?? displayedId
        
        // Generate navigation bar
        let navBar = renderNavigationBar(
            homeId: actualHomeId,
            displayedId: displayedId,
            isSourceVisible: sourceText != nil
        )
        
        // Generate family content with home parameter for links
        let familyHTML = renderStructuredFamilyContent(
            family: family,
            network: network,
            familyId: displayedId,
            homeId: actualHomeId,
            comparisonResult: comparisonResult,
            comparisonGroups: comparisonGroups,
            hiskiChildSearchRequestsByCouple: hiskiChildSearchRequestsByCouple,
            showsSourceMarkers: citationText == nil
        )
        let closeURL = "/family/\(urlEncode(displayedId))" + (displayedId == actualHomeId ? "" : "?home=\(urlEncode(actualHomeId))")
        let citationPanel = renderCitationPanel(citationText: citationText, errorMessage: errorMessage, closeURL: closeURL)
        let sourcePanel = renderSourcePanel(sourceText: sourceText)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(displayedId)) - Kalvian Roots</title>
            <style>
                \(cssStyles)
            </style>
        </head>
        <body>
            <div class="container">
                \(navBar)
                \(citationPanel)
                \(sourcePanel)
                <div class="family-content">
                    \(familyHTML)
                </div>
            </div>
            \(copyButtonScript)
            \(workupCopyScript)
            \(navigationScript)
        </body>
        </html>
        """
    }

    private static func renderFamilyWorkspaceHeader(
        family: Family,
        displayedId: String,
        homeId: String,
        sourceText: String?,
        comparisonResult: FamilyComparisonResult?,
        familySearchExtraction: FamilySearchFamilyExtraction?,
        familySearchPersonId: String?,
        workup: FamilyWorkup?
    ) -> String {
        let sourceURL = "/family/\(urlEncode(displayedId))/source" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        let workupURL = "/family/\(urlEncode(displayedId))/workup" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        let comparisonURL = "#children-comparison"
        let familySearchURL = familySearchPersonId.map { FamilySearchDOMService.detailsURL(for: $0) }
        let sourceStatus = sourceText == nil ? "Source hidden" : "Source visible"
        let comparisonStatus: String
        if let comparisonResult {
            comparisonStatus = "\(FamilyComparisonReviewDetector.displayRows(for: comparisonResult.rows).count) comparison rows"
        } else {
            comparisonStatus = "Comparison not loaded"
        }
        let familySearchStatus: String
        if let extraction = familySearchExtraction {
            familySearchStatus = extraction.isSuccessful
                ? "\(extraction.children.count) FamilySearch children"
                : "FamilySearch extraction failed"
        } else if familySearchPersonId != nil {
            familySearchStatus = "FamilySearch ready"
        } else {
            familySearchStatus = "No FamilySearch anchor"
        }
        let reviewStatus: String
        if let workup {
            reviewStatus = workup.actions.isEmpty
                ? "No queued actions"
                : "\(workup.actions.count) queued \(workup.actions.count == 1 ? "action" : "actions")"
        } else {
            reviewStatus = "Review queue not loaded"
        }

        let familySearchAction = familySearchURL.map {
            "<a class=\"family-workspace-action\" href=\"\(escapeHTML($0))\">FamilySearch</a>"
        } ?? ""
        let comparisonAction = comparisonResult == nil && familySearchPersonId == nil
            ? ""
            : "<a class=\"family-workspace-action\" href=\"\(escapeHTML(comparisonURL))\">Comparison</a>"
        let reviewAction = (workup?.actions.isEmpty == false)
            ? "<a class=\"family-workspace-action\" href=\"#family-review-queue\">Review</a>"
            : ""

        return """
        <section class="family-workspace" aria-label="Family review status">
            <div class="family-workspace-main">
                <div class="family-workspace-family">
                    <span class="family-workspace-title">\(escapeHTML(family.familyId))</span>
                    <span class="family-workspace-pages">Pages: \(escapeHTML(family.pageReferences.joined(separator: ", ")))</span>
                    <span>\(family.couples.count) \(family.couples.count == 1 ? "couple" : "couples")</span>
                    <span>\(family.allChildren.count) \(family.allChildren.count == 1 ? "child" : "children")</span>
                </div>
                <div class="family-workspace-status">
                    <span>\(escapeHTML(sourceStatus))</span>
                    <span>\(escapeHTML(comparisonStatus))</span>
                    <span>\(escapeHTML(familySearchStatus))</span>
                    <span>\(escapeHTML(reviewStatus))</span>
                </div>
            </div>
            <div class="family-workspace-actions">
                <a class="family-workspace-action" href="\(escapeHTML(sourceURL))">Source</a>
                <a class="family-workspace-action" href="\(escapeHTML(workupURL))">Workup</a>
                \(reviewAction)
                \(comparisonAction)
                \(familySearchAction)
            </div>
        </section>
        """
    }

    private static func renderFamilyReviewQueuePanel(
        workup: FamilyWorkup?,
        displayedId: String,
        homeId: String
    ) -> String {
        guard let workup, !workup.actions.isEmpty else {
            return ""
        }

        let workupURL = "/family/\(urlEncode(displayedId))/workup" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        let mismatchCount = workup.actions.filter { $0.type == "review.familysearch-id-mismatch" }.count
        let sourceUpdateCount = workup.actions.filter { $0.type == "source.update.familysearch-id" }.count
        let otherCount = workup.actions.count - mismatchCount - sourceUpdateCount
        let counts = [
            ("ID mismatches", mismatchCount),
            ("Source updates", sourceUpdateCount),
            ("Other", otherCount)
        ]
            .filter { $0.1 > 0 }
            .map { label, count in
                "<span>\(escapeHTML(label)): \(count)</span>"
            }
            .joined(separator: "\n")
        let displayedActions = workup.actions.prefix(5).map(renderFamilyReviewAction).joined(separator: "\n")
        let moreActions = workup.actions.count > 5
            ? "<p class=\"workup-muted\">\(workup.actions.count - 5) more \(workup.actions.count - 5 == 1 ? "action" : "actions") on the full workup page.</p>"
            : ""
        let reviewPacket = familyReviewPacketText(workup)

        return """
        <section class="family-review-panel" id="family-review-queue">
            <div class="family-review-header">
                <div>
                    <h2>Review Queue</h2>
                    <p class="workup-muted">\(workup.actions.count) queued \(workup.actions.count == 1 ? "action" : "actions") for collaborative review.</p>
                </div>
                <div class="family-review-tools">
                    <button type="button" class="workup-copy-button" onclick="copyFamilyReviewPacket(this)">Copy review packet</button>
                    <a class="family-workspace-action" href="\(escapeHTML(workupURL))#review-queue">Open full workup</a>
                </div>
            </div>
            <textarea id="familyReviewPacketText" class="copy-source-textarea" readonly>\(escapeHTML(reviewPacket))</textarea>
            <div class="family-review-counts">
                \(counts)
            </div>
            <ul class="family-review-actions">
                \(displayedActions)
            </ul>
            \(moreActions)
        </section>
        """
    }

    private static func renderStructuredFamilyContent(
        family: Family,
        network: FamilyNetwork?,
        familyId: String,
        homeId: String,
        comparisonResult: FamilyComparisonResult?,
        comparisonGroups: [FamilyChildrenComparisonGroup],
        hiskiChildSearchRequestsByCouple: [Int: HiskiService.FamilyBirthSearchRequest],
        showsSourceMarkers: Bool
    ) -> String {
        var html: [String] = []
        html.append("""
        <div class="family-header">
            <a class="family-title" href="/family/\(urlEncode(familyId))">\(escapeHTML(family.familyId))</a>
            <div class="family-pages">Pages: \(escapeHTML(family.pageReferences.joined(separator: ", ")))</div>
        </div>
        """)

        let comparisonGroupsByCouple = Dictionary(
            uniqueKeysWithValues: comparisonGroups.map { ($0.coupleIndex, $0) }
        )
        let primaryComparisonGroup = comparisonGroupsByCouple[0] ?? comparisonResult.flatMap {
            FamilyChildrenComparisonGroup.primaryCoupleFallback(for: family, result: $0)
        }

        for (index, couple) in family.couples.enumerated() {
            if index > 0 {
                html.append("<div class=\"section-header\">\(romanNumeral(index + 1)) puoliso</div>")
            }

            html.append(renderCoupleLines(
                couple: couple,
                previousCouple: index > 0 ? family.couples[index - 1] : nil,
                familyId: familyId,
                homeId: homeId,
                isAdditional: index > 0
            ))

            let comparisonGroup = comparisonGroupsByCouple[index] ?? (index == 0 ? primaryComparisonGroup : nil)
            if let comparisonGroup, !comparisonGroup.displayRows.isEmpty {
                if let request = hiskiChildSearchRequestsByCouple[index] {
                    html.append(renderLapsetHeader(url: request.url.absoluteString))
                } else {
                    html.append("<div class=\"section-header lapset-header\">Lapset</div>")
                }
                html.append(renderComparisonChildren(
                    comparisonGroup.displayRows,
                    couple: couple,
                    network: network,
                    familyId: familyId,
                    homeId: homeId,
                    showsSourceMarkers: showsSourceMarkers
                ))
            } else if !couple.children.isEmpty {
                if let request = hiskiChildSearchRequestsByCouple[index] {
                    html.append(renderLapsetHeader(url: request.url.absoluteString))
                } else {
                    html.append("<div class=\"section-header lapset-header\">Lapset</div>")
                }
                html.append(couple.children.map {
                    renderChildLine($0, couple: couple, network: network, familyId: familyId, homeId: homeId)
                }.joined(separator: "\n"))
            }

            if let childrenDied = couple.childrenDiedInfancy, childrenDied > 0 {
                html.append("<div class=\"family-note\">Lapsena kuollut \(childrenDied).</div>")
            }
        }

        if !family.notes.isEmpty {
            html.append(family.notes.map { "<div class=\"family-note\">\(escapeHTML(displayFootnoteText($0)))</div>" }.joined(separator: "\n"))
        }

        return html.joined(separator: "\n")
    }

    private static func renderCoupleLines(
        couple: Couple,
        previousCouple: Couple?,
        familyId: String,
        homeId: String,
        isAdditional: Bool
    ) -> String {
        var lines: [String] = []
        if !isAdditional {
            lines.append(renderPersonLine(couple.husband, familyId: familyId, homeId: homeId, symbol: "★"))
        }
        let spouse = isAdditional ? additionalSpouse(for: couple, previousCouple: previousCouple) : couple.wife
        lines.append(renderPersonLine(spouse, familyId: familyId, homeId: homeId, symbol: "★"))
        if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
            lines.append(renderMarriageLine(marriageDate, couple: couple, familyId: familyId, homeId: homeId))
        }
        return lines.joined(separator: "\n")
    }

    private static func additionalSpouse(for couple: Couple, previousCouple: Couple?) -> Person {
        guard let previousCouple else {
            return couple.wife
        }

        let husbandContinues = samePerson(couple.husband, previousCouple.husband)
        return husbandContinues ? couple.wife : couple.husband
    }

    private static func renderPersonLine(
        _ person: Person,
        familyId: String,
        homeId: String,
        symbol: String
    ) -> String {
        var parts = ["<span class=\"symbol\">\(escapeHTML(symbol))</span>"]
        if let birthDate = person.birthDate {
            parts.append(renderDateLink(birthDate, eventType: .birth, person: person, familyId: familyId, homeId: homeId))
        }
        parts.append(renderPersonLink(name: person.displayName, birthDate: person.birthDate, familyId: familyId, homeId: homeId))
        if let fsId = person.familySearchId {
            parts.append("<span class=\"familysearch-id\">&lt;\(escapeHTML(fsId))&gt;</span>")
        }
        if let deathDate = person.deathDate {
            parts.append("<span class=\"symbol\">†</span>")
            parts.append(renderDateLink(deathDate, eventType: .death, person: person, familyId: familyId, homeId: homeId))
        }
        if let asChild = person.asChild {
            parts.append(renderAsChildReference(asChild, homeId: homeId))
        }
        return "<div class=\"family-line\">\(parts.joined(separator: " "))</div>"
    }

    private static func renderMarriageLine(
        _ date: String,
        couple: Couple,
        familyId: String,
        homeId: String
    ) -> String {
        let href = hiskiMarriageSearchURL(
            husbandName: couple.husband.name,
            wifeName: couple.wife.name,
            date: date,
            parentBirthYear: CitationGenerator.extractBirthYear(from: couple.husband)
        )?.absoluteString ?? serverHiskiMarriageURL(
            date: date,
            couple: couple,
            familyId: familyId,
            homeId: homeId
        )
        return """
        <div class="family-line"><span class="symbol">∞</span> \(renderHiskiSearchAnchor(href: href, text: date, cssClass: "date-link"))</div>
        """
    }

    private static func renderLapsetHeader(url: String) -> String {
        """
        <a href="\(escapeHTML(url))"
           class="section-header hiski-child-results-link lapset-header"
           target="hiskiChildResults"
           title="Open complete HisKi child query results"
           onclick="return openHiskiResults(this.href)">Lapset</a>
        """
    }

    private static func renderChildLine(
        _ child: Person,
        couple: Couple,
        network: FamilyNetwork?,
        familyId: String,
        homeId: String,
        sourceMarkerHTML: String? = nil
    ) -> String {
        let childWithParents = child.withHiskiParentNames(
            father: couple.husband.displayName,
            mother: couple.wife.displayName
        )
        var parts = ["<span class=\"symbol\">★</span>"]
        if let birthDate = childWithParents.birthDate {
            parts.append(renderDateLink(birthDate, eventType: .birth, person: childWithParents, familyId: familyId, homeId: homeId))
        }
        parts.append(renderPersonLink(name: childWithParents.displayName, birthDate: childWithParents.birthDate, familyId: familyId, homeId: homeId))
        if let sourceMarkerHTML {
            parts.append(sourceMarkerHTML)
        }
        if let fsId = childWithParents.familySearchId {
            parts.append("<span class=\"familysearch-id\">&lt;\(escapeHTML(fsId))&gt;</span>")
        }

        let enhancedData = enhancedPersonData(for: childWithParents, network: network)

        if let deathDate = enhancedData?.deathDate {
            parts.append(renderEnhancedDeathDate(deathDate, person: childWithParents, familyId: familyId, homeId: homeId))
        } else if let deathDate = childWithParents.deathDate, !childWithParents.isMarried {
            parts.append("<span class=\"symbol\">†</span>")
            parts.append(renderDateLink(deathDate, eventType: .death, person: childWithParents, familyId: familyId, homeId: homeId))
        }

        if childWithParents.isMarried {
            parts.append("<span class=\"symbol\">∞</span>")
            if let marriageDate = enhancedData?.fullMarriageDate ?? childWithParents.fullMarriageDate ?? childWithParents.marriageDate {
                let displayDate = displayMarriageDate(marriageDate, parentBirthYear: CitationGenerator.extractBirthYear(from: childWithParents))
                parts.append(renderDateLink(displayDate, eventType: .marriage, person: childWithParents, familyId: familyId, homeId: homeId, isEnhanced: enhancedData?.fullMarriageDate != nil))
            }

            if let spouse = childWithParents.spouse {
                parts.append(renderPersonLink(name: spouse, birthDate: nil, familyId: familyId, homeId: homeId))
                if !childWithParents.noteMarkers.isEmpty {
                    parts.append(escapeHTML(childWithParents.noteMarkers.map(displayFootnoteMarker).joined(separator: " ")))
                }
            }

            if let spouseData = enhancedData?.spouse {
                parts.append(renderSpouseEnhancedDates(spouseData, familyId: familyId, homeId: homeId))
            }
        }
        if let asParent = childWithParents.asParent {
            parts.append(renderFamilyIdLink(asParent, homeId: homeId))
        }
        if !childWithParents.noteMarkers.isEmpty && !(childWithParents.spouse != nil && childWithParents.isMarried) {
            parts.append(escapeHTML(childWithParents.noteMarkers.map(displayFootnoteMarker).joined(separator: " ")))
        }
        return "<div class=\"family-line child-line\">\(parts.joined(separator: " "))</div>"
    }

    private static func renderComparisonChildren(
        _ rows: [FamilyComparisonDisplayRow],
        couple: Couple,
        network: FamilyNetwork?,
        familyId: String,
        homeId: String,
        showsSourceMarkers: Bool
    ) -> String {
        rows.map { displayRow in
            if let child = juuretChild(for: displayRow.match, in: couple) {
                return renderJuuretComparisonChild(
                    child,
                    displayRow: displayRow,
                    couple: couple,
                    network: network,
                    familyId: familyId,
                    homeId: homeId,
                    showsSourceMarkers: showsSourceMarkers
                )
            }
            return renderComparisonOnlyChild(displayRow, familyId: familyId, homeId: homeId, showsSourceMarkers: showsSourceMarkers)
        }.joined(separator: "\n")
    }

    private static func renderJuuretComparisonChild(
        _ child: Person,
        displayRow: FamilyComparisonDisplayRow,
        couple: Couple,
        network: FamilyNetwork?,
        familyId: String,
        homeId: String,
        showsSourceMarkers: Bool
    ) -> String {
        let row = displayRow.match
        let sourceMarkerHTML = showsSourceMarkers && (row.familySearch != nil || row.hiski != nil)
            ? "<span class=\"source-markers\">\(escapeHTML(sourceMarkers(for: row)))</span>"
            : nil
        var line = renderChildLine(
            child,
            couple: couple,
            network: network,
            familyId: familyId,
            homeId: homeId,
            sourceMarkerHTML: sourceMarkerHTML
        )
        var supplements: [String] = []
        if displayRow.reviewNote != nil {
            supplements.append("<span class=\"review-marker\">*</span>")
        }
        if let familySearchId = row.familySearch?.familySearchId,
           child.familySearchId != familySearchId {
            supplements.append("<span class=\"familysearch-id\">&lt;\(escapeHTML(familySearchId))&gt;</span>")
        }
        if !supplements.isEmpty {
            line = line.replacingOccurrences(of: "</div>", with: " \(supplements.joined(separator: " "))</div>")
        }
        return line
    }

    private static func renderComparisonOnlyChild(
        _ displayRow: FamilyComparisonDisplayRow,
        familyId: String,
        homeId: String,
        showsSourceMarkers: Bool
    ) -> String {
        let row = displayRow.match
        let date = displayDate(for: row)
        let name = displayName(for: row)
        var parts = [
            "<span class=\"symbol\">★</span>",
            escapeHTML(date),
            escapeHTML(name)
        ]
        if showsSourceMarkers {
            parts.append("<span class=\"source-markers\">\(escapeHTML(sourceMarkers(for: row)))</span>")
        }
        if displayRow.reviewNote != nil {
            parts.append("<span class=\"review-marker\">*</span>")
        }
        if let familySearchId = row.familySearch?.familySearchId {
            parts.append("<span class=\"familysearch-id\">&lt;\(escapeHTML(familySearchId))&gt;</span>")
        }
        return "<div class=\"family-line child-line comparison-only-child\">\(parts.joined(separator: " "))</div>"
    }

    private static func renderPersonLink(
        name: String,
        birthDate: String?,
        familyId: String,
        homeId: String
    ) -> String {
        let homeParam = (familyId == homeId) ? "" : "&home=\(urlEncode(homeId))"
        let params = buildQueryParams([
            "name": name,
            "birth": birthDate
        ])
        return "<a href=\"/family/\(urlEncode(familyId))/cite?\(params)\(homeParam)\" class=\"person-link\">\(escapeHTML(name))</a>"
    }

    private static func renderDateLink(
        _ date: String,
        eventType: EventType,
        person: Person,
        familyId: String,
        homeId: String,
        isEnhanced: Bool = false
    ) -> String {
        let linkClass = isEnhanced ? "date-link enhanced-date" : "date-link"
        let href = hiskiSearchURL(
            date: date,
            eventType: eventType,
            person: person
        )?.absoluteString ?? serverHiskiDateURL(
            date: date,
            eventType: eventType,
            person: person,
            familyId: familyId,
            homeId: homeId
        )
        return renderHiskiSearchAnchor(href: href, text: date, cssClass: linkClass)
    }

    private static func renderHiskiSearchAnchor(href: String, text: String, cssClass: String) -> String {
        """
        <a href="\(escapeHTML(href))" class="\(cssClass)" target="hiskiChildResults" onclick="return openHiskiResults(this.href)">\(escapeHTML(text))</a>
        """
    }

    private static func hiskiSearchURL(date: String, eventType: EventType, person: Person) -> URL? {
        let hiskiService = HiskiService(nameEquivalenceManager: NameEquivalenceManager())
        do {
            switch eventType {
            case .birth:
                return try hiskiService.birthSearchResultsURL(
                    name: person.name,
                    date: date,
                    fatherName: person.fatherName,
                    motherName: person.motherName,
                    parentBirthYear: CitationGenerator.extractBirthYear(from: person)
                )
            case .death:
                return try hiskiService.deathSearchResultsURL(name: person.name, date: date)
            case .marriage:
                guard let spouse = person.spouse else {
                    return nil
                }
                return try hiskiService.marriageSearchResultsURL(
                    husbandName: person.name,
                    wifeName: spouse,
                    date: date,
                    parentBirthYear: CitationGenerator.extractBirthYear(from: person)
                )
            case .baptism, .burial:
                return nil
            }
        } catch {
            return nil
        }
    }

    private static func hiskiMarriageSearchURL(
        husbandName: String,
        wifeName: String,
        date: String,
        parentBirthYear: Int?
    ) -> URL? {
        let hiskiService = HiskiService(nameEquivalenceManager: NameEquivalenceManager())
        return try? hiskiService.marriageSearchResultsURL(
            husbandName: husbandName,
            wifeName: wifeName,
            date: date,
            parentBirthYear: parentBirthYear
        )
    }

    private static func serverHiskiDateURL(
        date: String,
        eventType: EventType,
        person: Person,
        familyId: String,
        homeId: String
    ) -> String {
        let homeParam = (familyId == homeId) ? "" : "&home=\(urlEncode(homeId))"
        let params = buildQueryParams([
            "name": person.name,
            "birth": person.birthDate,
            "event": eventType.rawValue,
            "date": date,
            "father": person.fatherName,
            "mother": person.motherName
        ])
        return "/family/\(urlEncode(familyId))/hiski?\(params)\(homeParam)"
    }

    private static func serverHiskiMarriageURL(
        date: String,
        couple: Couple,
        familyId: String,
        homeId: String
    ) -> String {
        let homeParam = (familyId == homeId) ? "" : "&home=\(urlEncode(homeId))"
        let params = buildQueryParams([
            "spouse1": couple.husband.name,
            "birth1": couple.husband.birthDate,
            "spouse2": couple.wife.name,
            "birth2": couple.wife.birthDate,
            "event": "marriage",
            "date": date
        ])
        return "/family/\(urlEncode(familyId))/hiski?\(params)\(homeParam)"
    }

    private static func renderAsChildReference(_ id: String, homeId: String) -> String {
        "{ \(renderFamilyIdLink(id, homeId: homeId)) }"
    }

    private static func renderFamilyIdLink(
        _ id: String,
        homeId: String
    ) -> String {
        guard FamilyIDs.isValid(familyId: id) else {
            return "<span class=\"pseudo-family-id\">\(escapeHTML(id))</span>"
        }
        let homeParam = (id == homeId) ? "" : "?home=\(urlEncode(homeId))"
        return "<a href=\"/family/\(urlEncode(id))\(homeParam)\" class=\"family-link\">\(escapeHTML(id))</a>"
    }

    private static func renderEnhancedDeathDate(
        _ date: String,
        person: Person,
        familyId: String,
        homeId: String
    ) -> String {
        """
        <span class="enhanced-date">[d. \(renderDateLink(date, eventType: .death, person: person, familyId: familyId, homeId: homeId, isEnhanced: true))]</span>
        """
    }

    private static func renderSpouseEnhancedDates(
        _ spouse: HTMLSpouseEnhancedData,
        familyId: String,
        homeId: String
    ) -> String {
        if let birthDate = spouse.birthDate, let deathDate = spouse.deathDate {
            let birth = renderDateLink(
                birthDate,
                eventType: .birth,
                person: spouse.person(birthDate: birthDate, deathDate: deathDate),
                familyId: familyId,
                homeId: homeId,
                isEnhanced: true
            )
            let death = renderDateLink(
                deathDate,
                eventType: .death,
                person: spouse.person(birthDate: birthDate, deathDate: deathDate),
                familyId: familyId,
                homeId: homeId,
                isEnhanced: true
            )
            return "<span class=\"enhanced-date\">[\(birth)-\(death)]</span>"
        }

        if let birthDate = spouse.birthDate {
            let birth = renderDateLink(
                birthDate,
                eventType: .birth,
                person: spouse.person(birthDate: birthDate, deathDate: nil),
                familyId: familyId,
                homeId: homeId,
                isEnhanced: true
            )
            return "<span class=\"enhanced-date\">[\(birth)]</span>"
        }

        return ""
    }

    private static func enhancedPersonData(for person: Person, network: FamilyNetwork?) -> HTMLEnhancedPersonData? {
        guard let network, person.isMarried else {
            return nil
        }
        guard let asParentFamily = network.getAsParentFamily(for: person) else {
            return nil
        }
        guard let asParentPerson = matchingParent(for: person, in: asParentFamily) else {
            return nil
        }

        let spouseData = person.spouse.flatMap {
            enhancedSpouseData(spouseName: $0, from: asParentFamily, network: network)
        }

        return HTMLEnhancedPersonData(
            deathDate: asParentPerson.deathDate,
            fullMarriageDate: asParentPerson.fullMarriageDate ?? asParentFamily.primaryCouple?.fullMarriageDate,
            spouse: spouseData
        )
    }

    private static func matchingParent(for person: Person, in family: Family) -> Person? {
        if let birthDate = person.birthDate,
           let match = family.allParents.first(where: { $0.birthDate == birthDate }) {
            return match
        }

        let personName = person.name.lowercased()
        return family.allParents.first { $0.name.lowercased() == personName }
    }

    private static func enhancedSpouseData(
        spouseName: String,
        from asParentFamily: Family,
        network: FamilyNetwork
    ) -> HTMLSpouseEnhancedData? {
        let spouseNameLower = spouseName.lowercased()
        guard let spouseInFamily = asParentFamily.allParents.first(where: {
            $0.name.lowercased().contains(spouseNameLower) || spouseNameLower.contains($0.name.lowercased())
        }) else {
            return nil
        }

        let spouseForLookup = Person(name: spouseInFamily.name, birthDate: spouseInFamily.birthDate, noteMarkers: [])
        guard let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spouseForLookup) else {
            return HTMLSpouseEnhancedData(
                birthDate: spouseInFamily.birthDate,
                deathDate: spouseInFamily.deathDate,
                fullName: spouseName
            )
        }

        if let spouseAsChild = spouseAsChildFamily.allChildren.first(where: {
            $0.name.lowercased() == spouseInFamily.name.lowercased() || $0.birthDate == spouseInFamily.birthDate
        }) {
            return HTMLSpouseEnhancedData(
                birthDate: spouseAsChild.birthDate,
                deathDate: spouseAsChild.deathDate,
                fullName: spouseName
            )
        }

        return HTMLSpouseEnhancedData(
            birthDate: spouseInFamily.birthDate,
            deathDate: spouseInFamily.deathDate,
            fullName: spouseName
        )
    }

    private static func juuretChild(for row: FamilyComparisonResult.Match, in couple: Couple) -> Person? {
        guard let juuret = row.juuretKalvialla else {
            return nil
        }
        return couple.children.first { child in
            child.name == juuret.rawName && sameGenealogyDate(child.birthDate, juuret.birthDate)
        }
    }

    private static func displayDate(for row: FamilyComparisonResult.Match) -> String {
        formatUnionDate(row.juuretKalvialla?.birthDate ?? row.hiski?.birthDate ?? row.familySearch?.birthDate)
    }

    private static func displayName(for row: FamilyComparisonResult.Match) -> String {
        row.juuretKalvialla?.rawName
            ?? row.hiski?.rawName
            ?? row.familySearch?.rawName
            ?? row.identity.canonicalName
    }

    private static func sourceMarkers(for row: FamilyComparisonResult.Match) -> String {
        var markers: [String] = []
        if row.juuretKalvialla != nil {
            markers.append("J")
        }
        if row.hiski != nil {
            markers.append("H")
        }
        if row.familySearch != nil {
            markers.append("FS")
        }
        return markers.joined(separator: ", ")
    }

    private static func formatUnionDate(_ date: Date?) -> String {
        guard let date else {
            return "unknown"
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.day, .month, .year], from: date)

        if components.day == 1, components.month == 1, let year = components.year {
            return String(year)
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private static func displayMarriageDate(_ date: String, parentBirthYear: Int?) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains(".") {
            let components = trimmed.components(separatedBy: ".")
            if components.count == 3,
               components[2].count == 2,
               let twoDigitYear = Int(components[2]) {
                let fullYear = CitationGenerator.inferCentury(
                    for: twoDigitYear,
                    parentBirthYear: parentBirthYear
                )
                return "\(components[0]).\(components[1]).\(fullYear)"
            }
        }

        if trimmed.count == 2, let twoDigitYear = Int(trimmed) {
            return String(CitationGenerator.inferCentury(
                for: twoDigitYear,
                parentBirthYear: parentBirthYear
            ))
        }

        return trimmed
    }

    private static func samePerson(_ left: Person, _ right: Person) -> Bool {
        left.name == right.name && left.birthDate == right.birthDate
    }

    private static func sameGenealogyDate(_ genealogyDate: String?, _ date: Date?) -> Bool {
        guard let genealogyDate, let date else {
            return genealogyDate == nil && date == nil
        }
        return genealogyDate == formatUnionDate(date)
    }

    private static func romanNumeral(_ number: Int) -> String {
        switch number {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        case 5: return "V"
        case 6: return "VI"
        case 7: return "VII"
        case 8: return "VIII"
        case 9: return "IX"
        case 10: return "X"
        default: return String(number)
        }
    }

    private static func familyReviewPacketText(_ workup: FamilyWorkup) -> String {
        var lines = [
            "Kalvian Roots Review Queue",
            "Family: \(workup.familyId)",
            "Actions: \(workup.actions.count)"
        ]

        for (index, action) in workup.actions.enumerated() {
            lines.append("")
            lines.append("\(index + 1). \(action.type)\(action.personName.map { " - \($0)" } ?? "")")
            lines.append("ID: \(action.id)")
            lines.append("Label: \(action.label)")
            if let approvalPrompt = action.approvalPrompt {
                lines.append("Approval: \(approvalPrompt)")
            }
            if let context = action.context {
                lines.append(contentsOf: familyReviewPacketContextLines(context))
            }
            if action.type == "source.update.familysearch-id" ||
                action.type == "review.familysearch-id-mismatch" {
                lines.append("Dry run: \(sourceEditCommand(action, commandName: "source-edit-dry-run"))")
                lines.append("Apply: \(sourceEditCommand(action, commandName: "source-edit-apply"))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func familyReviewPacketContextLines(_ context: FamilyWorkup.ActionContext) -> [String] {
        var lines: [String] = []
        if let coupleIndex = context.coupleIndex {
            lines.append("Couple: \(coupleIndex + 1)")
        }
        if let status = context.status {
            lines.append("Status: \(status)")
        }
        if let birthDate = context.birthDate {
            lines.append("Birth: \(birthDate)")
        }
        lines.append(contentsOf: [
            renderPlainCandidateSummary(label: "Juuret", candidate: context.juuret),
            renderPlainCandidateSummary(label: "HisKi", candidate: context.hiski),
            renderPlainCandidateSummary(label: "FamilySearch", candidate: context.familySearch)
        ].compactMap { $0 })
        return lines
    }

    private static func renderPlainCandidateSummary(
        label: String,
        candidate: FamilyWorkup.CandidateSummary?
    ) -> String? {
        guard let candidate else {
            return nil
        }

        var parts = ["\(label): \(candidate.name)"]
        if let birthDate = candidate.birthDate {
            parts.append(birthDate)
        }
        if let familySearchId = candidate.familySearchId {
            parts.append(familySearchId)
        }
        if let hiskiCitation = candidate.hiskiCitation {
            parts.append(hiskiCitation)
        }
        return parts.joined(separator: ", ")
    }

    private static func renderFamilyReviewAction(_ action: FamilyWorkup.ActionSummary) -> String {
        let personHTML = action.personName.map { " - \(escapeHTML($0))" } ?? ""
        let approvalHTML = action.approvalPrompt.map {
            "<div class=\"workup-action-prompt\">\(escapeHTML($0))</div>"
        } ?? ""
        let sourceEditCommandHTML = renderSourceEditCommands(action)
        let actionURL = actionDetailURL(action, homeId: nil)

        return """
        <li>
            <strong>\(escapeHTML(action.type))</strong>: \(escapeHTML(action.label))\(personHTML)
            <div class="workup-action-copy-row">
                <code class="workup-action-id">\(escapeHTML(action.id))</code>
                <button type="button" class="workup-copy-button" data-copy="\(escapeHTML(action.id))" onclick="copyWorkupValue(this)">Copy ID</button>
                <a class="workup-copy-button" href="\(escapeHTML(actionURL))">Open</a>
            </div>
            \(approvalHTML)
            \(sourceEditCommandHTML)
        </li>
        """
    }
    
    // MARK: - Navigation Bar
    
    private static func renderNavigationBar(
        homeId: String,
        displayedId: String,
        isSourceVisible: Bool = false,
        isWorkupVisible: Bool = false
    ) -> String {
        // Calculate navigation targets based on homeId
        let previousId = FamilyIDs.previousFamilyBefore(homeId)
        let nextId = FamilyIDs.nextFamilyAfter(homeId)
        let canGoPrevious = previousId != nil
        let canGoNext = nextId != nil
        
        // Generate button URLs
        let previousURL = previousId.map { "/family/\(urlEncode($0))" } ?? ""
        let familyURL = "/family/\(urlEncode(displayedId))" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        let nextURL = nextId.map { "/family/\(urlEncode($0))" } ?? ""
        let reloadURL = "/family/\(urlEncode(homeId))?reload=1"
        let sourceURL = isSourceVisible
            ? familyURL
            : "/family/\(urlEncode(displayedId))/source" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        let sourceTitle = isSourceVisible ? "Hide source text" : "View source text"
        let workupURL = isWorkupVisible
            ? familyURL
            : "/family/\(urlEncode(displayedId))/workup" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        let workupTitle = isWorkupVisible ? "View family display" : "View family workup"
        
        return """
        <div class="nav-bar">
            <div class="nav-buttons">
                <a href="\(previousURL)" class="nav-btn\(canGoPrevious ? "" : " disabled")" \(canGoPrevious ? "" : "onclick='return false;'")>←</a>
                <a href="\(nextURL)" class="nav-btn\(canGoNext ? "" : " disabled")" \(canGoNext ? "" : "onclick='return false;'")>→</a>
                <a href="\(reloadURL)" class="nav-btn">↺</a>
                <a href="\(sourceURL)" class="nav-btn" title="\(sourceTitle)">📄</a>
                <a href="\(workupURL)" class="nav-btn" title="\(workupTitle)">⚙</a>
            </div>
            <form method="GET" action="/family" class="nav-form" onsubmit="showLoading(event)">
                <div class="input-wrapper">
                    <input type="text" id="familyInput" name="id" value="\(escapeHTML(homeId))" class="family-input" placeholder="Enter family ID..." required autocomplete="off">
                    <button type="button" class="clear-btn" onclick="clearInput()" style="display: none;">✕</button>
                </div>
            </form>
            <div class="loading-indicator" id="loadingIndicator" style="display: none;">
                <div class="spinner"></div>
                <span id="loadingText">Loading...</span>
            </div>
        </div>
        """
    }

    // MARK: - Token Rendering

    private static func renderTokens(
        _ tokens: [FamilyToken],
        familyId: String,
        homeId: String,
        hiskiChildSearchRequestsByCouple: [Int: HiskiService.FamilyBirthSearchRequest]
    ) -> String {
        var html = ""
        var lapsetSectionIndex = 0

        for token in tokens {
            switch token {
            case .text(let str):
                let renderedText = str
                    .replacingOccurrences(of: "as_child", with: "a child in")
                    .replacingOccurrences(of: "as_parent", with: "parents in")
                html += escapeHTML(renderedText)

            case .person(let name, let birthDate):
                // Preserve home parameter in citation links
                let homeParam = (familyId == homeId) ? "" : "&home=\(urlEncode(homeId))"
                let params = buildQueryParams([
                    "name": name,
                    "birth": birthDate
                ])
                html += """
                <a href="/family/\(urlEncode(familyId))/cite?\(params)\(homeParam)"
                   class="person-link">\(escapeHTML(name))</a>
                """

            case .date(let date, let eventType, let person, let spouse1, let spouse2):
                // Preserve home parameter in HisKi links
                let homeParam = (familyId == homeId) ? "" : "&home=\(urlEncode(homeId))"
                
                if eventType == .marriage, let s1 = spouse1, let s2 = spouse2 {
                    // Marriage date
                    let params = buildQueryParams([
                        "spouse1": s1.name,
                        "birth1": s1.birthDate,
                        "spouse2": s2.name,
                        "birth2": s2.birthDate,
                        "event": "marriage",
                        "date": date
                    ])
                    html += """
                    <a href="/family/\(urlEncode(familyId))/hiski?\(params)\(homeParam)"
                       class="date-link">\(escapeHTML(date))</a>
                    """
                } else if let person = person {
                    // Birth or death date
                    let params = buildQueryParams([
                        "name": person.name,
                        "birth": person.birthDate,
                        "event": eventType.rawValue,
                        "date": date,
                        "father": person.fatherName,
                        "mother": person.motherName
                    ])
                    html += """
                    <a href="/family/\(urlEncode(familyId))/hiski?\(params)\(homeParam)"
                       class="date-link">\(escapeHTML(date))</a>
                    """
                } else {
                    // Non-clickable date
                    html += escapeHTML(date)
                }

            case .familyId(let id):
                if FamilyIDs.isValid(familyId: id) {
                    // Family reference links preserve home parameter
                    let homeParam = (id == homeId) ? "" : "?home=\(urlEncode(homeId))"
                    html += """
                    <a href="/family/\(urlEncode(id))\(homeParam)"
                       class="family-link">\(escapeHTML(id))</a>
                    """
                } else {
                    // Pseudo-family ID, not clickable
                    html += escapeHTML(id)
                }

            case .enhanced(let content):
                html += """
                        <span class="enhanced">\(escapeHTML(content))</span>
                        """

            case .symbol(let sym):
                html += """
                        <span class="symbol">\(escapeHTML(sym))</span>
                        """

            case .lineBreak:
                html += "<br>"

            case .sectionHeader(let title):
                if title == "Lapset" {
                    let request = hiskiChildSearchRequestsByCouple[lapsetSectionIndex]
                    lapsetSectionIndex += 1

                    if let request {
                        html += """
                                <a href="\(escapeHTML(request.url.absoluteString))"
                                   class="section-header hiski-child-results-link"
                                   target="hiskiChildResults"
                                   title="Open complete HisKi child query results"
                                   onclick="return openHiskiResults(this.href)">\(escapeHTML(title))</a>
                                """
                    } else {
                        html += """
                                <div class="section-header">\(escapeHTML(title))</div>
                                """
                    }
                } else {
                    html += """
                            <div class="section-header">\(escapeHTML(title))</div>
                            """
                }
            }
        }

        return html
    }

    // MARK: - Citation Panel

    private static func renderCitationPanel(citationText: String? = nil, errorMessage: String? = nil, closeURL: String) -> String {
        guard citationText != nil || errorMessage != nil else {
            return ""
        }

        if let error = errorMessage {
            return """
            <div class="error-panel">
                <div class="citation-header">
                    <div class="error-title">Error</div>
                    <a class="citation-close-button" href="\(escapeHTML(closeURL))" aria-label="Close citation panel">&times;</a>
                </div>
                <div class="error-message">\(escapeHTML(error))</div>
            </div>
            """
        }

        if let citation = citationText {
            return """
            <div class="citation-panel">
                <div class="citation-header">
                    <span class="citation-title">Citation</span>
                    <div class="citation-actions">
                        <button id="copyBtn" class="copy-button" onclick="copyCitation()">Copy</button>
                        <a class="citation-close-button" href="\(escapeHTML(closeURL))" aria-label="Close citation panel">&times;</a>
                    </div>
                </div>
                <textarea id="citationText" class="citation-textarea" spellcheck="false">\(escapeHTML(citation))</textarea>
                <div id="copyHint" class="copy-hint" style="display: none;">Press Cmd+C / Ctrl+C to copy</div>
            </div>
            """
        }

        return ""
    }

    // MARK: - Source Text Panel

    private static func renderSourcePanel(sourceText: String? = nil) -> String {
        guard let source = sourceText else {
            return ""
        }

        return """
        <div class="source-panel">
            <div class="source-header">
                <span class="source-title">📄 Source Text from JuuretKälviällä.roots</span>
            </div>
            <pre class="source-text">\(escapeHTML(source))</pre>
        </div>
        """
    }

    // MARK: - Temporary Comparison Panel

    private static func renderComparisonPanel(
        family: Family,
        comparisonResult: FamilyComparisonResult?,
        familySearchExtraction: FamilySearchFamilyExtraction?,
        familySearchPersonId: String?
    ) -> String {
        guard comparisonResult != nil || familySearchPersonId != nil else {
            return ""
        }

        let coupleHeader: String
        if let couple = family.primaryCouple {
            let marriage = familySearchExtraction?.marriage?.date
                ?? couple.fullMarriageDate
                ?? couple.marriageDate
                ?? "unknown marriage"
            coupleHeader = "\(couple.husband.displayName) + \(couple.wife.displayName) - \(marriage)"
        } else {
            coupleHeader = family.familyId
        }

        let extractionSummary: String
        if let extraction = familySearchExtraction {
            if extraction.isSuccessful {
                extractionSummary = """
                <div class="fs-debug-summary">
                    FamilySearch source person: \(escapeHTML(extraction.sourcePersonId)).
                    Context URL: \(escapeHTML(extraction.url ?? "unknown")).
                    Context host: \(escapeHTML(extraction.detectedHost ?? "unknown")).
                    Expected: \(escapeHTML(extraction.expectedPersonId ?? "unknown")).
                    Detected: \(escapeHTML(extraction.detectedPersonId ?? "unknown")).
                    Spouse groups: \(extraction.spouseGroupCount ?? extraction.spouseGroups?.count ?? 0).
                    Children markers: \(extraction.childrenMarkerCount ?? 0).
                    Raw candidates: \(extraction.rawCandidateChildCount ?? 0).
                    Children extracted: \(extraction.children.count).
                </div>
                """
            } else {
                extractionSummary = """
                <div class="fs-debug-summary">
                    FamilySearch extraction failed (\(escapeHTML(extraction.status ?? "extractorError"))): \(escapeHTML(extraction.failureReason ?? "unknown failure")).
                    Context URL: \(escapeHTML(extraction.url ?? "unknown")).
                    Context host: \(escapeHTML(extraction.detectedHost ?? "unknown")).
                    Expected: \(escapeHTML(extraction.expectedPersonId ?? "unknown")).
                    Detected: \(escapeHTML(extraction.detectedPersonId ?? "unknown")).
                    Family Members found: \(extraction.familyMembersSectionFound.map { $0 ? "yes" : "no" } ?? "unknown").
                    Spouses and Children found: \(extraction.spousesAndChildrenSectionFound.map { $0 ? "yes" : "no" } ?? "unknown").
                </div>
                """
            }
        } else if let familySearchPersonId {
            let familySearchURL = FamilySearchDOMService.detailsURL(for: familySearchPersonId)
            extractionSummary = """
            <div class="fs-debug-summary">
                FamilySearch children have not been imported for this family.
                Open the FamilySearch person Details page in Kalvian Roots to extract children with the in-app WebKit workflow.
            </div>
            <a class="fs-action" href="\(escapeHTML(familySearchURL))">Open FamilySearch Details page</a>
            """
        } else {
            extractionSummary = """
            <div class="fs-debug-summary">
                No FamilySearch parent ID is available in this Juuret family.
            </div>
            """
        }

        let rowsHTML: String
        let comparisonRows = comparisonResult.map { FamilyComparisonReviewDetector.displayRows(for: $0.rows) } ?? []
        let reviewCount = comparisonRows.filter { $0.reviewNote != nil }.count
        let comparisonSummary: String
        if let comparisonResult {
            comparisonSummary = "\(comparisonRows.count) \(comparisonRows.count == 1 ? "row" : "rows"), \(reviewCount) needing review"
            let rows = comparisonRows.map { displayRow in
                let match = displayRow.match
                let displayName = match.juuretKalvialla?.rawName
                    ?? match.hiski?.rawName
                    ?? match.familySearch?.rawName
                    ?? "(unknown)"
                let reviewNote = displayRow.reviewNote
                let includeSourceNames = reviewNote != nil
                let nameClass = reviewNote == nil ? "" : " class=\"comparison-review-name\""
                let nameTitle = reviewNote.map { " title=\"\(escapeHTML($0.message))\"" } ?? ""
                let status = reviewNote == nil
                    ? comparisonStatus(for: match)
                    : "Review name discrepancy"

                return """
                <tr>
                    <td\(nameClass)\(nameTitle)>\(escapeHTML(displayName))</td>
                    <td>\(renderCandidateCell(match.juuretKalvialla, includeName: includeSourceNames))</td>
                    <td>\(renderCandidateCell(match.hiski, includeName: includeSourceNames))</td>
                    <td>\(renderCandidateCell(match.familySearch, includeName: includeSourceNames))</td>
                    <td>\(escapeHTML(status))</td>
                </tr>
                """
            }.joined(separator: "\n")

            rowsHTML = rows.isEmpty
                ? "<tr><td colspan=\"5\">No comparison rows.</td></tr>"
                : rows
        } else {
            comparisonSummary = "Comparison has not run"
            rowsHTML = "<tr><td colspan=\"5\">Comparison has not run.</td></tr>"
        }
        let clipboardText = comparisonClipboardText(
            comparisonResult: comparisonResult,
            familySearchExtraction: familySearchExtraction,
            familySearchPersonId: familySearchPersonId
        )

        return """
        <div class="comparison-panel" id="children-comparison">
            <div class="comparison-header">
                <div>
                    <div class="comparison-title">Children Comparison</div>
                    <div class="comparison-couple">\(escapeHTML(coupleHeader))</div>
                    <div class="comparison-summary">\(escapeHTML(comparisonSummary))</div>
                </div>
                <button type="button" class="copy-button comparison-copy-button" onclick="copyComparisonText()">Copy comparison text</button>
            </div>
            <textarea id="comparisonText" class="copy-source-textarea" readonly>\(escapeHTML(clipboardText))</textarea>
            \(extractionSummary)
            <div class="comparison-table-wrap">
                <table class="comparison-table">
                    <thead>
                        <tr>
                            <th>Child name</th>
                            <th>Juuret</th>
                            <th>HisKi</th>
                            <th>FamilySearch</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        \(rowsHTML)
                    </tbody>
                </table>
            </div>
        </div>
        """
    }

    private static func comparisonClipboardText(
        comparisonResult: FamilyComparisonResult?,
        familySearchExtraction: FamilySearchFamilyExtraction?,
        familySearchPersonId: String?
    ) -> String {
        let debugMessage: String
        if let extraction = familySearchExtraction {
            debugMessage = extraction.isSuccessful
                ? "FamilySearch comparison ready"
                : "FamilySearch extraction failed (\(extraction.status ?? "extractorError")): \(extraction.failureReason ?? "unknown failure")"
        } else if comparisonResult != nil {
            debugMessage = "FamilySearch comparison ready"
        } else if familySearchPersonId != nil {
            debugMessage = "FamilySearch children have not been imported for this family."
        } else {
            debugMessage = "Comparison has not run"
        }

        return FamilySearchComparisonClipboardFormatter.text(
            debugMessage: debugMessage,
            debugLines: [],
            rows: comparisonResult?.rows ?? [],
            status: comparisonStatus(for:)
        )
    }

    private static func renderCandidateCell(_ candidate: PersonCandidate?, includeName: Bool = false) -> String {
        guard let candidate else {
            return "No"
        }

        var parts = ["Yes"]
        if includeName {
            parts.append(escapeHTML(candidate.rawName))
        }
        if let familySearchId = candidate.familySearchId {
            parts.append("&lt;\(escapeHTML(familySearchId))&gt;")
        }
        if let birthDate = candidate.birthDate {
            parts.append(escapeHTML(formatComparisonDate(birthDate)))
        }
        if let deathDate = candidate.deathDate {
            parts.append("d. \(escapeHTML(formatComparisonDate(deathDate)))")
        }

        return parts.joined(separator: "<br>")
    }

    private static func comparisonStatus(for match: FamilyComparisonResult.Match) -> String {
        let canonicalNames = [
            match.juuretKalvialla?.identity.canonicalName,
            match.hiski?.identity.canonicalName,
            match.familySearch?.identity.canonicalName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hasNameMismatch = Set(canonicalNames).count > 1

        switch (match.juuretKalvialla, match.hiski, match.familySearch) {
        case (.some, .some, .some):
            return hasNameMismatch ? "Name mismatch" : "Present in all three"
        case (.some, .some, nil):
            return "Missing in FamilySearch"
        case (.some, nil, nil):
            return "Juuret-only"
        case (nil, .some, nil):
            return "HisKi-only"
        case (nil, nil, .some(let familySearch)):
            return familySearch.birthDate == nil
                ? "FamilySearch date needed"
                : "FamilySearch-only"
        case (.some, nil, .some):
            return hasNameMismatch ? "Name mismatch" : "Missing in HisKi"
        case (nil, .some, .some):
            return hasNameMismatch ? "Name mismatch" : "Missing in Juuret"
        case (nil, nil, nil):
            return "Unknown"
        }
    }

    private static func formatComparisonDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - CSS Styles

    private static var cssStyles: String {
        return """
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        .nav-bar {
            background: white;
            padding: 15px 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 15px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .nav-buttons {
            display: flex;
            gap: 8px;
        }
        .nav-btn {
            background: #0066cc;
            color: white;
            border: none;
            padding: 8px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 18px;
            text-decoration: none;
            display: inline-block;
            transition: background 0.2s;
        }
        .nav-btn:hover:not(.disabled) {
            background: #0052a3;
        }
        .nav-btn.disabled {
            background: #ccc;
            cursor: not-allowed;
            opacity: 0.6;
        }
        .nav-form {
            flex: 1;
            max-width: 400px;
        }
        .input-wrapper {
            position: relative;
            width: 100%;
        }
        .family-input {
            width: 100%;
            padding: 8px 32px 8px 12px;
            border: 2px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
        }
        .family-input:focus {
            outline: none;
            border-color: #0066cc;
        }
        .clear-btn {
            position: absolute;
            right: 6px;
            top: 50%;
            transform: translateY(-50%);
            background: #e0e0e0;
            border: none;
            color: #666;
            font-size: 16px;
            line-height: 1;
            cursor: pointer;
            padding: 0;
            width: 20px;
            height: 20px;
            border-radius: 50%;
            display: none;
            align-items: center;
            justify-content: center;
        }
        .clear-btn:hover {
            background: #d0d0d0;
            color: #333;
        }
        .loading-indicator {
            display: flex;
            align-items: center;
            gap: 10px;
            color: #666;
            font-size: 14px;
        }
        .spinner {
            width: 20px;
            height: 20px;
            border: 3px solid #f3f3f3;
            border-top: 3px solid #0066cc;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .nav-link {
            color: #0066cc;
            text-decoration: none;
            font-weight: 500;
        }
        .nav-link:hover {
            text-decoration: underline;
        }
        .family-id-nav {
            font-size: 18px;
            font-weight: bold;
            color: #333;
        }
        .family-workspace {
            background: white;
            padding: 10px 12px;
            border-radius: 8px;
            margin-bottom: 12px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            display: flex;
            justify-content: space-between;
            gap: 12px;
            align-items: center;
        }
        .family-workspace-main {
            display: flex;
            gap: 12px;
            align-items: center;
            flex-wrap: wrap;
        }
        .family-workspace-family,
        .family-workspace-status,
        .family-workspace-actions {
            display: flex;
            gap: 8px;
            align-items: center;
            flex-wrap: wrap;
        }
        .family-workspace-title {
            font-weight: 700;
            color: #0066cc;
            font-size: 15px;
        }
        .family-workspace-pages {
            color: #666;
        }
        .family-workspace-family span,
        .family-workspace-status span {
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 2px 7px;
            background: #fff;
            color: #555;
            font-size: 13px;
        }
        .family-workspace-family .family-workspace-title {
            border: none;
            padding-left: 0;
            color: #0066cc;
        }
        .family-workspace-family .family-workspace-pages {
            border: none;
            padding-left: 0;
            color: #666;
        }
        .family-workspace-action {
            display: inline-block;
            border: 1px solid #0066cc;
            border-radius: 4px;
            padding: 3px 8px;
            color: #0066cc;
            background: #fff;
            text-decoration: none;
            font-size: 13px;
        }
        .family-workspace-action:hover {
            background: #eef6ff;
        }
        @media (max-width: 760px) {
            .family-workspace {
                align-items: flex-start;
                flex-direction: column;
            }
            .family-review-header {
                flex-direction: column;
            }
        }
        .family-content {
            background: #fefdf8;
            padding: 24px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            font-size: 16px;
            line-height: 1.3;
        }
        .family-header {
            margin-bottom: 12px;
        }
        .family-title {
            color: #0066cc;
            font-size: 18px;
            font-weight: 700;
            text-decoration: none;
        }
        .family-pages {
            color: #666;
            font-size: 14px;
            margin-top: 4px;
        }
        .family-line {
            min-height: 21px;
            white-space: normal;
        }
        .child-line {
            display: flex;
            align-items: baseline;
            gap: 6px;
            flex-wrap: wrap;
        }
        .lapset-header {
            margin-top: 8px;
            margin-bottom: 4px;
        }
        .familysearch-id,
        .source-markers {
            color: #666;
            font-size: 13px;
        }
        .source-markers {
            font-weight: 700;
        }
        .enhanced-date,
        .enhanced-date a {
            color: #8b4513;
        }
        .review-marker {
            color: #b45f06;
            font-weight: 700;
        }
        .pseudo-family-id {
            color: #666;
            font-style: italic;
        }
        .family-note {
            color: #666;
            font-size: 14px;
            font-style: italic;
            margin-top: 4px;
        }
        .family-review-panel {
            background: white;
            padding: 16px 18px;
            border-radius: 8px;
            margin-top: 16px;
            margin-bottom: 16px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .family-review-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            gap: 12px;
            margin-bottom: 10px;
        }
        .family-review-header h2 {
            font-size: 18px;
            margin: 0 0 2px 0;
        }
        .family-review-tools {
            display: flex;
            gap: 8px;
            align-items: center;
            flex-wrap: wrap;
            justify-content: flex-end;
        }
        .family-review-counts {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-bottom: 10px;
        }
        .family-review-counts span {
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 2px 7px;
            background: #fff;
            color: #555;
            font-size: 13px;
        }
        .family-review-actions {
            margin-left: 22px;
        }
        .family-review-actions li {
            margin-bottom: 12px;
        }
        .section-header {
            font-size: 18px;
            font-weight: bold;
            margin-top: 20px;
            margin-bottom: 10px;
            color: #333;
        }
        .person-link, .date-link, .family-link {
            color: #0066cc;
            text-decoration: underline;
            cursor: pointer;
        }
        .person-link:hover, .date-link:hover, .family-link:hover {
            color: #0052a3;
            text-decoration: underline;
        }
        .person-link:focus, .date-link:focus, .family-link:focus {
            outline: 2px solid #0066cc;
            outline-offset: 2px;
        }
        .hiski-child-results-link {
            display: block;
            color: #0066cc;
            text-decoration: underline;
            cursor: pointer;
        }
        .hiski-child-results-link:hover {
            color: #0052a3;
        }
        .enhanced {
            color: #8b4513;
        }
        .symbol {
            color: #333;
        }
        .citation-panel {
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .citation-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        .citation-actions {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .citation-title {
            font-size: 18px;
            font-weight: bold;
            color: #333;
        }
        .citation-textarea {
            width: 100%;
            min-height: 200px;
            padding: 15px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
            font-size: 14px;
            resize: vertical;
            background: #f9f9f9;
        }
        .citation-textarea:focus {
            outline: none;
            border-color: #0066cc;
            background: white;
        }
        .copy-button {
            background: #0066cc;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
        }
        .copy-button:hover {
            background: #0052a3;
        }
        .citation-close-button {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 34px;
            height: 34px;
            border: 1px solid #d6d6d6;
            border-radius: 4px;
            color: #333;
            background: #f7f7f7;
            font-size: 22px;
            line-height: 1;
            text-decoration: none;
        }
        .citation-close-button:hover {
            background: #ececec;
        }
        .copy-hint {
            margin-top: 10px;
            padding: 8px 12px;
            background: #e7f3ff;
            border: 1px solid #b3d9ff;
            border-radius: 4px;
            color: #0066cc;
            font-size: 13px;
        }
        .error-panel {
            background: #fee;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            border: 1px solid #fcc;
        }
        .error-title {
            font-size: 18px;
            font-weight: bold;
            color: #dc3545;
            margin-bottom: 10px;
        }
        .error-message {
            color: #721c24;
        }
        .source-panel {
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .source-header {
            margin-bottom: 15px;
        }
        .source-title {
            font-size: 16px;
            font-weight: bold;
            color: #333;
        }
        .source-text {
            width: 100%;
            padding: 15px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
            font-size: 13px;
            background: #f9f9f9;
            white-space: pre-wrap;
            overflow-x: auto;
            line-height: 1.5;
            color: #333;
        }
        .comparison-panel {
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .comparison-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 12px;
        }
        .comparison-title {
            font-size: 18px;
            font-weight: bold;
            color: #333;
        }
        .comparison-couple, .comparison-summary, .fs-debug-summary {
            color: #666;
            font-size: 13px;
            margin-top: 4px;
        }
        .comparison-copy-button {
            white-space: nowrap;
        }
        .copy-source-textarea {
            position: absolute;
            left: -10000px;
            top: auto;
            width: 1px;
            height: 1px;
            opacity: 0;
        }
        .fs-action {
            display: inline-block;
            margin-top: 10px;
            margin-right: 8px;
            padding: 8px 12px;
            border-radius: 4px;
            border: none;
            background: #0066cc;
            color: white;
            font-size: 13px;
            text-decoration: none;
            cursor: pointer;
        }
        .fs-action:hover {
            background: #0052a3;
        }
        .fs-action:disabled {
            cursor: wait;
            opacity: 0.65;
        }
        .comparison-table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
            margin-top: 12px;
        }
        .comparison-table-wrap {
            overflow-x: auto;
        }
        .comparison-table-wrap .comparison-table {
            min-width: 760px;
        }
        .comparison-table th,
        .comparison-table td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
            vertical-align: top;
        }
        .comparison-table th {
            background: #f5f5f5;
            font-weight: 700;
        }
        .comparison-table td.comparison-review-name {
            background: #fce4ec;
            color: #ad1457;
        }
        .workup-panel {
            background: white;
            padding: 24px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .workup-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            gap: 16px;
            margin-bottom: 20px;
        }
        .workup-header h1 {
            margin: 0 0 4px 0;
            font-size: 24px;
        }
        .workup-section {
            border-top: 1px solid #e5e5e5;
            padding-top: 16px;
            margin-top: 16px;
        }
        .workup-section h2 {
            margin: 0 0 8px 0;
            font-size: 17px;
        }
        .workup-section ul {
            margin: 8px 0 0 20px;
            padding: 0;
        }
        .workup-section li {
            margin-bottom: 8px;
        }
        .workup-review-nav {
            display: flex;
            gap: 8px;
            flex-wrap: wrap;
            margin-top: 10px;
        }
        .workup-review-link {
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 5px 9px;
            color: #333;
            background: #fafafa;
            text-decoration: none;
            font-size: 13px;
        }
        .workup-review-link:hover {
            background: #f0f0f0;
        }
        .workup-review-link.disabled {
            color: #888;
            background: #f0f0f0;
            cursor: default;
        }
        .action-detail-nav {
            display: flex;
            align-items: center;
            gap: 8px;
            flex-wrap: wrap;
            margin: 0 0 12px 0;
        }
        .review-queue-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 12px;
        }
        .review-queue-table th,
        .review-queue-table td {
            border: 1px solid #ddd;
            padding: 7px 8px;
            text-align: left;
            vertical-align: top;
        }
        .review-queue-table th {
            background: #f5f5f5;
        }
        .workup-action-id {
            word-break: break-word;
        }
        .workup-action-copy-row {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-top: 3px;
            flex-wrap: wrap;
        }
        .workup-action-command {
            word-break: break-word;
        }
        .workup-copy-button {
            border: 1px solid #ccc;
            background: #fff;
            color: #333;
            border-radius: 4px;
            padding: 3px 8px;
            font: inherit;
            font-size: 12px;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
        }
        .workup-copy-button:hover {
            background: #f3f3f3;
        }
        .workup-action-prompt {
            margin-top: 4px;
            font-weight: 700;
        }
        .workup-action-context {
            margin-top: 4px;
        }
        .workup-action-context div {
            margin-top: 2px;
        }
        .source-edit-preview {
            margin-top: 14px;
            border-top: 1px solid #e0e0e0;
            padding-top: 12px;
        }
        .source-edit-preview h3 {
            margin: 0 0 8px 0;
            font-size: 16px;
        }
        .source-edit-line-label {
            margin-top: 8px;
            font-weight: 700;
        }
        .source-edit-preview pre {
            white-space: pre-wrap;
            overflow-wrap: anywhere;
            background: #fafafa;
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 8px;
            margin: 4px 0 0 0;
        }
        .workup-muted {
            color: #666;
            font-size: 13px;
        }
        .workup-action-form {
            margin-top: 12px;
        }
        """
    }

    static func renderWorkup(
        _ workup: FamilyWorkup,
        family: Family,
        homeId: String
    ) -> String {
        let navBar = renderNavigationBar(
            homeId: homeId,
            displayedId: family.familyId,
            isWorkupVisible: true
        )
        let jsonURL = "/family/\(urlEncode(family.familyId))/workup.json"
        let extractionURL = "/family/\(urlEncode(family.familyId))/familysearch-extract" + (family.familyId == homeId ? "" : "?home=\(urlEncode(homeId))")
        let familySearchActionHTML: String
        if workup.familySearch.extractionStatus == "available" {
            familySearchActionHTML = ""
        } else if workup.familySearch.anchorPersonId != nil {
            familySearchActionHTML = """
            <form method="post" action="\(extractionURL)" class="workup-action-form">
                <button type="submit" class="fs-action">Run FamilySearch Extraction</button>
            </form>
            """
        } else {
            familySearchActionHTML = ""
        }
        let reviewQueueHTML = renderWorkupReviewQueue(workup.actions, homeId: homeId)
        let actionSectionsHTML = renderWorkupActionSections(workup.actions, homeId: homeId)
        let couplesHTML = workup.couples.map { couple in
            """
            <section class="workup-section">
                <h2>Couple \(couple.index + 1)</h2>
                <p>\(escapeHTML(couple.husband.displayName)) and \(escapeHTML(couple.wife.displayName))</p>
                <p>Children: \(couple.childCount)</p>
            </section>
            """
        }.joined(separator: "\n")
        let hiskiHTML = workup.hiskiQueries.isEmpty
            ? "<li>No HisKi birth-span queries available.</li>"
            : workup.hiskiQueries.map { query in
                """
                <li>
                    <a href="\(escapeHTML(query.url))">\(escapeHTML(query.label))</a>
                    <span class="workup-muted">couple \(query.coupleIndex + 1), \(query.startYear)-\(query.endYear), \(escapeHTML(query.sourceDescription))</span>
                </li>
                """
            }.joined(separator: "\n")
        let comparisonHTML = renderWorkupComparison(workup.comparison)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(workup.familyId)) Workup - Kalvian Roots</title>
            <style>
                \(cssStyles)
            </style>
        </head>
        <body>
            <div class="container">
                \(navBar)
                <div class="workup-panel">
                    <div class="workup-header">
                        <div>
                            <h1>\(escapeHTML(workup.familyId)) Workup</h1>
                            <p class="workup-muted">Source text: \(workup.sourceTextAvailable ? "\(workup.sourceTextLineCount) lines" : "not available")</p>
                        </div>
                        <a class="fs-action" href="\(jsonURL)">JSON</a>
                    </div>

                    <section class="workup-section">
                        <h2>FamilySearch</h2>
                        <p>Status: \(escapeHTML(workup.familySearch.extractionStatus))</p>
                        <p>Anchor: \(escapeHTML(workup.familySearch.anchorPersonId ?? "none"))</p>
                        <p>Extracted children: \(workup.familySearch.extractedChildCount)</p>
                        \(workup.familySearch.note.map { "<p class=\"workup-muted\">\(escapeHTML($0))</p>" } ?? "")
                        \(familySearchActionHTML)
                    </section>

                    \(couplesHTML)

                    <section class="workup-section">
                        <h2>HisKi Queries</h2>
                        <ul>\(hiskiHTML)</ul>
                    </section>

                    \(reviewQueueHTML)
                    \(actionSectionsHTML)

                    \(comparisonHTML)
                </div>
            </div>
            \(workupCopyScript)
        </body>
        </html>
        """
    }

    static func renderWorkupActionDetail(
        _ workup: FamilyWorkup,
        family: Family,
        homeId: String,
        actionId: String,
        sourceText: String? = nil
    ) -> String {
        let navBar = renderNavigationBar(homeId: homeId, displayedId: family.familyId)
        let workupURL = "/family/\(urlEncode(family.familyId))/workup" + (family.familyId == homeId ? "" : "?home=\(urlQueryEncode(homeId))")
        let action = workup.actions.first { $0.id == actionId }
        let navigationHTML = renderActionDetailNavigation(
            workup.actions,
            currentActionId: actionId,
            homeId: homeId
        )
        let title = action.map { "\($0.type) - \(family.familyId)" } ?? "Action Not Found - \(family.familyId)"
        let actionHTML: String
        if let action {
            let previewHTML = sourceText.map {
                renderSourceEditPreview(action, sourceText: $0)
            } ?? ""
            actionHTML = """
            <section class="workup-section">
                <h2>\(escapeHTML(action.type))\(action.personName.map { " - \(escapeHTML($0))" } ?? "")</h2>
                <p>\(escapeHTML(action.label))</p>
                <ul>\(renderWorkupAction(action, homeId: homeId))</ul>
                \(previewHTML)
            </section>
            """
        } else {
            actionHTML = """
            <section class="workup-section">
                <h2>Action Not Found</h2>
                <p class="workup-muted">No queued action matched this action ID.</p>
                <div class="workup-action-copy-row">
                    <code class="workup-action-id">\(escapeHTML(actionId))</code>
                    <button type="button" class="workup-copy-button" data-copy="\(escapeHTML(actionId))" onclick="copyWorkupValue(this)">Copy ID</button>
                </div>
            </section>
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(title))</title>
            <style>
                \(cssStyles)
            </style>
        </head>
        <body>
            <div class="container">
                \(navBar)
                <div class="workup-panel">
                    <div class="workup-header">
                        <div>
                            <h1>\(escapeHTML(family.familyId)) Action</h1>
                            <p class="workup-muted">Dedicated review view for one queued workup action.</p>
                        </div>
                        <a class="fs-action" href="\(escapeHTML(workupURL))#review-queue">Review Queue</a>
                    </div>
                    \(navigationHTML)
                    \(actionHTML)
                    \(navigationHTML)
                </div>
            </div>
            \(workupCopyScript)
        </body>
        </html>
        """
    }

    private static func renderActionDetailNavigation(
        _ actions: [FamilyWorkup.ActionSummary],
        currentActionId: String,
        homeId: String
    ) -> String {
        guard let index = actions.firstIndex(where: { $0.id == currentActionId }) else {
            return ""
        }

        let previousHTML = index > 0
            ? "<a class=\"workup-review-link\" href=\"\(escapeHTML(actionDetailURL(actions[index - 1], homeId: homeId)))\">Previous</a>"
            : "<span class=\"workup-review-link disabled\">Previous</span>"
        let nextHTML = index + 1 < actions.count
            ? "<a class=\"workup-review-link\" href=\"\(escapeHTML(actionDetailURL(actions[index + 1], homeId: homeId)))\">Next</a>"
            : "<span class=\"workup-review-link disabled\">Next</span>"

        return """
        <nav class="action-detail-nav">
            \(previousHTML)
            <span class="workup-muted">Action \(index + 1) of \(actions.count)</span>
            \(nextHTML)
        </nav>
        """
    }

    private static func renderWorkupReviewQueue(
        _ actions: [FamilyWorkup.ActionSummary],
        homeId: String
    ) -> String {
        guard !actions.isEmpty else {
            return """
            <section class="workup-section" id="review-queue">
                <h2>Review Queue</h2>
                <p class="workup-muted">No queued actions.</p>
            </section>
            """
        }

        let mismatchCount = actions.filter { $0.type == "review.familysearch-id-mismatch" }.count
        let sourceUpdateCount = actions.filter { $0.type == "source.update.familysearch-id" }.count
        let otherCount = actions.count - mismatchCount - sourceUpdateCount
        let links = [
            ("familysearch-id-mismatches", "ID Mismatches", mismatchCount),
            ("source-updates", "Source Updates", sourceUpdateCount),
            ("other-actions", "Other Actions", otherCount)
        ]
            .filter { $0.2 > 0 }
            .map { id, label, count in
                "<a class=\"workup-review-link\" href=\"#\(id)\">\(label) (\(count))</a>"
            }
            .joined(separator: "\n")
        let rows = renderWorkupReviewQueueRows(actions, homeId: homeId)

        return """
        <section class="workup-section" id="review-queue">
            <h2>Review Queue</h2>
            <p class="workup-muted">\(actions.count) queued \(actions.count == 1 ? "action" : "actions") for collaborative review.</p>
            <nav class="workup-review-nav">
                \(links)
            </nav>
            <table class="review-queue-table">
                <thead>
                    <tr>
                        <th>Type</th>
                        <th>Person</th>
                        <th>Status</th>
                        <th>Birth</th>
                        <th>Action</th>
                    </tr>
                </thead>
                <tbody>
                    \(rows)
                </tbody>
            </table>
        </section>
        """
    }

    private static func renderWorkupReviewQueueRows(
        _ actions: [FamilyWorkup.ActionSummary],
        homeId: String
    ) -> String {
        actions.map { action in
            let actionURL = actionDetailURL(action, homeId: homeId)
            return """
            <tr>
                <td>\(escapeHTML(reviewQueueTypeLabel(action.type)))</td>
                <td>\(escapeHTML(action.personName ?? ""))</td>
                <td>\(escapeHTML(action.context?.status ?? ""))</td>
                <td>\(escapeHTML(action.context?.birthDate ?? ""))</td>
                <td>
                    <a class="workup-copy-button" href="\(escapeHTML(actionURL))">Open</a>
                    <button type="button" class="workup-copy-button" data-copy="\(escapeHTML(action.id))" onclick="copyWorkupValue(this)">Copy ID</button>
                </td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func reviewQueueTypeLabel(_ type: String) -> String {
        switch type {
        case "review.familysearch-id-mismatch":
            return "ID mismatch"
        case "source.update.familysearch-id":
            return "Source update"
        case "review.comparison":
            return "Comparison review"
        case "citation.juuret":
            return "Juuret citation"
        case "familysearch.extract":
            return "FamilySearch extraction"
        default:
            return type
        }
    }

    private static func renderWorkupActionSections(
        _ actions: [FamilyWorkup.ActionSummary],
        homeId: String
    ) -> String {
        guard !actions.isEmpty else {
            return ""
        }

        let mismatches = actions.filter { $0.type == "review.familysearch-id-mismatch" }
        let sourceUpdates = actions.filter { $0.type == "source.update.familysearch-id" }
        let otherActions = actions.filter {
            $0.type != "review.familysearch-id-mismatch" &&
                $0.type != "source.update.familysearch-id"
        }

        return [
            renderWorkupActionSection(
                id: "familysearch-id-mismatches",
                title: "FamilySearch ID Mismatches",
                actions: mismatches,
                homeId: homeId
            ),
            renderWorkupActionSection(
                id: "source-updates",
                title: "Source Updates",
                actions: sourceUpdates,
                homeId: homeId
            ),
            renderWorkupActionSection(
                id: "other-actions",
                title: "Other Actions",
                actions: otherActions,
                homeId: homeId
            )
        ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func renderWorkupActionSection(
        id: String,
        title: String,
        actions: [FamilyWorkup.ActionSummary],
        homeId: String
    ) -> String {
        guard !actions.isEmpty else {
            return ""
        }

        return """
        <section class="workup-section" id="\(id)">
            <h2>\(escapeHTML(title))</h2>
            <ul>\(actions.map { renderWorkupAction($0, homeId: homeId) }.joined(separator: "\n"))</ul>
        </section>
        """
    }

    private static func renderWorkupAction(
        _ action: FamilyWorkup.ActionSummary,
        homeId: String
    ) -> String {
        let personHTML = action.personName.map { " - \(escapeHTML($0))" } ?? ""
        let approvalHTML = action.approvalPrompt.map {
            "<div class=\"workup-action-prompt\">\(escapeHTML($0))</div>"
        } ?? ""
        let contextHTML = action.context.map(renderWorkupActionContext) ?? ""
        let sourceEditCommandHTML = renderSourceEditCommands(action)
        let actionURL = actionDetailURL(action, homeId: homeId)

        return """
        <li>
            <strong>\(escapeHTML(action.type))</strong>: \(escapeHTML(action.label))\(personHTML)
            <div class="workup-action-copy-row">
                <code class="workup-action-id">\(escapeHTML(action.id))</code>
                <button type="button" class="workup-copy-button" data-copy="\(escapeHTML(action.id))" onclick="copyWorkupValue(this)">Copy ID</button>
                <a class="workup-copy-button" href="\(escapeHTML(actionURL))">Open</a>
            </div>
            \(approvalHTML)
            \(contextHTML)
            \(sourceEditCommandHTML)
        </li>
        """
    }

    private static func renderSourceEditCommands(_ action: FamilyWorkup.ActionSummary) -> String {
        guard action.type == "source.update.familysearch-id" ||
                action.type == "review.familysearch-id-mismatch" else {
            return ""
        }

        let dryRunCommand = sourceEditCommand(action, commandName: "source-edit-dry-run")
        let applyCommand = sourceEditCommand(action, commandName: "source-edit-apply")

        return """
        <div class="workup-action-copy-row workup-muted">
            <code class="workup-action-command">\(escapeHTML(dryRunCommand))</code>
            <button type="button" class="workup-copy-button" data-copy="\(escapeHTML(dryRunCommand))" onclick="copyWorkupValue(this)">Copy Dry Run</button>
        </div>
        <div class="workup-action-copy-row workup-muted">
            <code class="workup-action-command">\(escapeHTML(applyCommand))</code>
            <button type="button" class="workup-copy-button" data-copy="\(escapeHTML(applyCommand))" onclick="copyWorkupValue(this)">Copy Apply</button>
        </div>
        """
    }

    private static func sourceEditCommand(
        _ action: FamilyWorkup.ActionSummary,
        commandName: String
    ) -> String {
        [
            "Tools/juuret-project/juuret-project",
            commandName,
            shellQuote(action.familyId),
            shellQuote(action.id)
        ].joined(separator: " ")
    }

    private static func renderSourceEditPreview(
        _ action: FamilyWorkup.ActionSummary,
        sourceText: String
    ) -> String {
        guard action.type == "source.update.familysearch-id" ||
                action.type == "review.familysearch-id-mismatch" else {
            return ""
        }

        let matches = matchingSourceLines(sourceText: sourceText, action: action)
        if matches.count != 1 {
            let message: String
            if matches.isEmpty {
                message = "No unique source line match found from action name/date context."
            } else {
                message = "Multiple matching source lines found; manual review is required."
            }
            let matchHTML = matches.map { lineNumber, line in
                "<div><strong>\(lineNumber):</strong> \(escapeHTML(line))</div>"
            }.joined(separator: "\n")
            return """
            <div class="source-edit-preview">
                <h3>Source Edit Dry Run</h3>
                <p class="workup-muted">\(escapeHTML(message))</p>
                \(matchHTML)
                <p class="workup-muted">No source edit was applied.</p>
            </div>
            """
        }

        let match = matches[0]
        let proposal = proposedSourceEdit(action, sourceLine: match.line)
        guard let newLine = proposal.newLine else {
            return """
            <div class="source-edit-preview">
                <h3>Source Edit Dry Run</h3>
                <p class="workup-muted">\(escapeHTML(proposal.reason ?? "No source edit is available."))</p>
                <p class="workup-muted">No source edit was applied.</p>
            </div>
            """
        }

        return """
        <div class="source-edit-preview">
            <h3>Source Edit Dry Run</h3>
            <p class="workup-muted">Line: \(match.lineNumber)</p>
            <div class="source-edit-line-label">Old</div>
            <pre>\(escapeHTML(match.line))</pre>
            <div class="source-edit-line-label">New</div>
            <pre>\(escapeHTML(newLine))</pre>
            <p class="workup-muted">No source edit was applied.</p>
        </div>
        """
    }

    private static func matchingSourceLines(
        sourceText: String,
        action: FamilyWorkup.ActionSummary
    ) -> [(lineNumber: Int, line: String)] {
        let juuret = action.context?.juuret
        let name = (juuret?.name ?? action.personName ?? "").lowercased()
        let dateVariants = sourceDateVariants(action.context?.birthDate)

        return sourceText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, lineSubstring in
                let line = String(lineSubstring)
                let folded = line.lowercased()
                let hasName = !name.isEmpty && folded.contains(name)
                let hasDate = dateVariants.contains { line.contains($0) }
                if hasName && (hasDate || dateVariants.isEmpty) {
                    return (offset + 1, line)
                }
                return nil
            }
    }

    private static func sourceDateVariants(_ isoDate: String?) -> [String] {
        guard let isoDate, !isoDate.isEmpty else {
            return []
        }

        var variants = [isoDate]
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        if parts.count == 3 {
            let year = parts[0]
            let month = parts[1]
            let day = parts[2]
            variants.append("\(day).\(month).\(year)")
            variants.append(String(format: "%02d.%02d.%04d", day, month, year))
        }
        var seen: Set<String> = []
        return variants.filter { seen.insert($0).inserted }
    }

    private static func proposedSourceEdit(
        _ action: FamilyWorkup.ActionSummary,
        sourceLine: String
    ) -> (newLine: String?, reason: String?) {
        let juuret = action.context?.juuret
        let familySearch = action.context?.familySearch
        let newId = action.personId ?? familySearch?.familySearchId
        let oldId = juuret?.familySearchId
        let personName = juuret?.name ?? action.personName

        guard let newId, !newId.isEmpty else {
            return (nil, "No FamilySearch ID is available for the proposed edit.")
        }

        if action.type == "source.update.familysearch-id" {
            if sourceLine.range(of: #"<[A-Z0-9]{4}-[A-Z0-9]{3,}>"#, options: .regularExpression) != nil {
                return (nil, "Matched source line already contains a FamilySearch ID.")
            }
            guard let personName, sourceLine.contains(personName) else {
                return (nil, "Matched source line does not contain the Juuret person name exactly.")
            }
            guard let nameRange = sourceLine.range(of: personName) else {
                return (nil, "Matched source line does not contain the Juuret person name exactly.")
            }
            return (sourceLine.replacingOccurrences(of: personName, with: "\(personName) <\(newId)>", options: [], range: nameRange), nil)
        }

        if action.type == "review.familysearch-id-mismatch" {
            guard let oldId, !oldId.isEmpty else {
                return (nil, "Juuret does not provide the old FamilySearch ID needed for replacement.")
            }
            let oldToken = "<\(oldId)>"
            guard sourceLine.contains(oldToken) else {
                return (nil, "Matched source line does not contain \(oldToken).")
            }
            return (sourceLine.replacingOccurrences(of: oldToken, with: "<\(newId)>"), nil)
        }

        return (nil, "This action type does not support a source edit dry run.")
    }

    private static func actionDetailURL(
        _ action: FamilyWorkup.ActionSummary,
        homeId: String?
    ) -> String {
        var queryItems = ["action=\(urlQueryEncode(action.id))"]
        if let homeId, homeId != action.familyId {
            queryItems.append("home=\(urlQueryEncode(homeId))")
        }
        return "/family/\(urlEncode(action.familyId))/workup-action?\(queryItems.joined(separator: "&"))"
    }

    private static func renderWorkupActionContext(_ context: FamilyWorkup.ActionContext) -> String {
        var rows: [String] = []

        if let coupleIndex = context.coupleIndex {
            rows.append("Couple \(coupleIndex + 1)")
        }

        if let status = context.status {
            let date = context.birthDate.map { ", \($0)" } ?? ""
            rows.append("\(status)\(date)")
        } else if let birthDate = context.birthDate {
            rows.append(birthDate)
        }

        rows.append(contentsOf: [
            renderWorkupCandidateSummary(label: "Juuret", candidate: context.juuret),
            renderWorkupCandidateSummary(label: "HisKi", candidate: context.hiski),
            renderWorkupCandidateSummary(label: "FamilySearch", candidate: context.familySearch)
        ].compactMap { $0 })

        guard !rows.isEmpty else {
            return ""
        }

        return """
        <div class="workup-action-context workup-muted">
            \(rows.map { "<div>\(escapeHTML($0))</div>" }.joined(separator: "\n"))
        </div>
        """
    }

    private static func renderWorkupCandidateSummary(
        label: String,
        candidate: FamilyWorkup.CandidateSummary?
    ) -> String? {
        guard let candidate else {
            return nil
        }

        var parts = ["\(label): \(candidate.name)"]
        if let birthDate = candidate.birthDate {
            parts.append(birthDate)
        }
        if let familySearchId = candidate.familySearchId {
            parts.append(familySearchId)
        }
        if let hiskiCitation = candidate.hiskiCitation {
            parts.append(hiskiCitation)
        }
        return parts.joined(separator: ", ")
    }

    private static func renderWorkupComparison(_ comparison: FamilyWorkup.ComparisonSummary?) -> String {
        guard let comparison else {
            return """
            <section class="workup-section">
                <h2>Comparison</h2>
                <p>No comparison is available.</p>
            </section>
            """
        }

        let rows = comparison.rows.map { row in
            let statusHTML = row.reviewNote.map {
                "\(escapeHTML(row.status))<div class=\"workup-muted\">\(escapeHTML($0))</div>"
            } ?? escapeHTML(row.status)
            return """
            <tr>
                <td>\(escapeHTML(row.identityName))</td>
                <td>\(escapeHTML(row.birthDate ?? ""))</td>
                <td>\(statusHTML)</td>
                <td>\(escapeHTML(row.juuret?.name ?? ""))</td>
                <td>\(escapeHTML(row.hiski?.name ?? ""))</td>
                <td>\(escapeHTML(row.familySearch?.name ?? ""))</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <section class="workup-section">
            <h2>Comparison</h2>
            <p class="workup-muted">Rows: \(comparison.rowCount), matches: \(comparison.matchCount), Juuret-only: \(comparison.juuretOnlyCount), HisKi-only: \(comparison.hiskiOnlyCount), FamilySearch-only: \(comparison.familySearchOnlyCount)</p>
            <table class="comparison-table">
                <thead>
                    <tr>
                        <th>Identity</th>
                        <th>Birth</th>
                        <th>Status</th>
                        <th>Juuret</th>
                        <th>HisKi</th>
                        <th>FamilySearch</th>
                    </tr>
                </thead>
                <tbody>
                    \(rows)
                </tbody>
            </table>
        </section>
        """
    }

    // MARK: - JavaScript

    private static var copyButtonScript: String {
        return """
        <script>
        function copyCitation() {
            const textarea = document.getElementById('citationText');
            const hint = document.getElementById('copyHint');

            if (textarea) {
                textarea.focus();
                textarea.select();
                hint.style.display = 'block';

                setTimeout(() => {
                    hint.style.display = 'none';
                }, 3000);
            }
        }

        function copyComparisonText() {
            const textarea = document.getElementById('comparisonText');
            if (!textarea) {
                return;
            }

            textarea.focus();
            textarea.select();
            document.execCommand('copy');

            const button = document.querySelector('.comparison-copy-button');
            if (button) {
                const originalText = button.textContent;
                button.textContent = 'Copied';
                setTimeout(() => {
                    button.textContent = originalText;
                }, 1500);
            }
        }
        </script>
        """
    }

    private static var workupCopyScript: String {
        """
        <script>
        function copyWorkupValue(button) {
            const value = button.getAttribute('data-copy') || '';
            const originalText = button.textContent;

            function markCopied() {
                button.textContent = 'Copied';
                setTimeout(() => {
                    button.textContent = originalText;
                }, 1500);
            }

            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(value).then(markCopied);
                return;
            }

            const textarea = document.createElement('textarea');
            textarea.value = value;
            document.body.appendChild(textarea);
            textarea.focus();
            textarea.select();
            document.execCommand('copy');
            textarea.remove();
            markCopied();
        }

        function copyFamilyReviewPacket(button) {
            const textarea = document.getElementById('familyReviewPacketText');
            if (!textarea) {
                return;
            }

            const originalText = button?.textContent;
            function markCopied() {
                if (!button || !originalText) {
                    return;
                }
                button.textContent = 'Copied';
                setTimeout(() => {
                    button.textContent = originalText;
                }, 1500);
            }

            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(textarea.value).then(markCopied);
                return;
            }

            textarea.focus();
            textarea.select();
            document.execCommand('copy');
            markCopied();
        }
        </script>
        """
    }
    
    private static var navigationScript: String {
        return """
        <script>
        // Show/hide clear button based on input content
        const familyInput = document.getElementById('familyInput');
        const clearBtn = document.querySelector('.clear-btn');
        
        if (familyInput && clearBtn) {
            // Initial state
            clearBtn.style.display = familyInput.value ? 'flex' : 'none';
            
            // Update on input
            familyInput.addEventListener('input', function() {
                clearBtn.style.display = this.value ? 'flex' : 'none';
            });
        }
        
        // Clear input function
        function clearInput() {
            const input = document.getElementById('familyInput');
            if (input) {
                input.value = '';
                input.focus();
                const clearBtn = document.querySelector('.clear-btn');
                if (clearBtn) {
                    clearBtn.style.display = 'none';
                }
            }
        }
        
        // Show loading indicator
        function showLoading(event) {
            const input = document.getElementById('familyInput');
            const form = document.querySelector('.nav-form');
            const loadingIndicator = document.getElementById('loadingIndicator');
            const loadingText = document.getElementById('loadingText');
            
            if (input && loadingIndicator && loadingText) {
                const familyId = input.value.trim().toUpperCase();
                loadingText.textContent = 'Loading ' + familyId + '...';
                form.style.display = 'none';
                loadingIndicator.style.display = 'flex';
            }
        }

        function openHiskiResults(url) {
            const popup = window.open(url, 'hiskiChildResults', 'width=1200,height=900,scrollbars=yes,resizable=yes');
            if (popup) {
                popup.focus();
                return false;
            }
            return true;
        }
        
        // Show loading when clicking navigation buttons
        document.querySelectorAll('.nav-btn:not(.disabled)').forEach(btn => {
            btn.addEventListener('click', function(e) {
                const href = this.getAttribute('href');
                if (href && href !== '#' && !this.classList.contains('disabled')) {
                    const form = document.querySelector('.nav-form');
                    const loadingIndicator = document.getElementById('loadingIndicator');
                    const loadingText = document.getElementById('loadingText');
                    
                    if (loadingIndicator && loadingText) {
                        // Extract family ID from href
                        const match = href.match(/\\/family\\/([^?]+)/);
                        if (match) {
                            const familyId = decodeURIComponent(match[1]);
                            loadingText.textContent = 'Loading ' + familyId + '...';
                        } else {
                            loadingText.textContent = 'Loading...';
                        }
                        if (form) form.style.display = 'none';
                        loadingIndicator.style.display = 'flex';
                    }
                }
            });
        });
        </script>
        """
    }

    // MARK: - Helper Functions

    private static func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeJavaScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func shellQuote(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    
    private static func urlEncode(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? string
    }

    private static func urlQueryEncode(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized.hasPrefix("127.0.0.1")
            || normalized.hasPrefix("localhost")
            || normalized.hasPrefix("[::1]")
            || normalized.hasPrefix("::1")
    }

    private static func buildQueryParams(_ params: [String: String?]) -> String {
        var components: [String] = []
        for (key, value) in params {
            if let value = value, !value.isEmpty {
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                components.append("\(encodedKey)=\(encodedValue)")
            }
        }
        return components.joined(separator: "&")
    }
}

private struct HTMLEnhancedPersonData {
    let deathDate: String?
    let fullMarriageDate: String?
    let spouse: HTMLSpouseEnhancedData?
}

private struct HTMLSpouseEnhancedData {
    let birthDate: String?
    let deathDate: String?
    let fullName: String

    func person(birthDate: String?, deathDate: String?) -> Person {
        Person(name: fullName, birthDate: birthDate, deathDate: deathDate, noteMarkers: [])
    }
}

#endif // os(macOS)
