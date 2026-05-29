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
                <form method="GET" action="/family" id="familyForm">
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
                function updateWorkupPreview() {
                    const preview = document.getElementById('workupPreview');
                    preview.textContent = window.location.origin + workupURLFor(canonicalFamilyId());
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
        familySearchExtraction: FamilySearchFamilyExtraction? = nil,
        familySearchPersonId: String? = nil,
        hiskiChildSearchRequestsByCouple: [Int: HiskiService.FamilyBirthSearchRequest] = [:]
    ) -> String {
        let tokenizer = FamilyTokenizer()
        let tokens = tokenizer.tokenizeFamily(family: family, network: network)

        // Determine home and displayed IDs
        let displayedId = family.familyId
        let actualHomeId = homeId ?? displayedId
        
        // Generate navigation bar
        let navBar = renderNavigationBar(homeId: actualHomeId, displayedId: displayedId)
        
        // Generate family content with home parameter for links
        let familyHTML = renderTokens(
            tokens,
            familyId: displayedId,
            homeId: actualHomeId,
            hiskiChildSearchRequestsByCouple: hiskiChildSearchRequestsByCouple
        )
        let citationPanel = renderCitationPanel(citationText: citationText, errorMessage: errorMessage)
        let sourcePanel = renderSourcePanel(sourceText: sourceText)
        let comparisonPanel = renderComparisonPanel(
            family: family,
            comparisonResult: comparisonResult,
            familySearchExtraction: familySearchExtraction,
            familySearchPersonId: familySearchPersonId
        )

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
                \(comparisonPanel)
                <div class="family-content">
                    \(familyHTML)
                </div>
            </div>
            \(copyButtonScript)
            \(navigationScript)
        </body>
        </html>
        """
    }
    
    // MARK: - Navigation Bar
    
    private static func renderNavigationBar(homeId: String, displayedId: String) -> String {
        // Calculate navigation targets based on homeId
        let previousId = FamilyIDs.previousFamilyBefore(homeId)
        let nextId = FamilyIDs.nextFamilyAfter(homeId)
        let canGoPrevious = previousId != nil
        let canGoNext = nextId != nil
        let isViewingHome = (homeId == displayedId)
        
        // Generate button URLs
        let previousURL = previousId.map { "/family/\(urlEncode($0))" } ?? ""
        let homeURL = "/family/\(urlEncode(homeId))"
        let nextURL = nextId.map { "/family/\(urlEncode($0))" } ?? ""
        let reloadURL = "/family/\(urlEncode(homeId))?reload=1"
        let sourceURL = "/family/\(urlEncode(displayedId))/source" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        let workupURL = "/family/\(urlEncode(displayedId))/workup" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        
        return """
        <div class="nav-bar">
            <div class="nav-buttons">
                <a href="\(previousURL)" class="nav-btn\(canGoPrevious ? "" : " disabled")" \(canGoPrevious ? "" : "onclick='return false;'")>←</a>
                <a href="\(homeURL)" class="nav-btn\(isViewingHome ? " disabled" : "")" \(isViewingHome ? "onclick='return false;'" : "")>⌂</a>
                <a href="\(nextURL)" class="nav-btn\(canGoNext ? "" : " disabled")" \(canGoNext ? "" : "onclick='return false;'")>→</a>
                <a href="\(reloadURL)" class="nav-btn">↺</a>
                <a href="\(sourceURL)" class="nav-btn" title="View source text">📄</a>
                <a href="\(workupURL)" class="nav-btn" title="View family workup">⚙</a>
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
                        "date": date
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
                                   onclick="return openHiskiChildResults(this.href)">\(escapeHTML(title))</a>
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

    private static func renderCitationPanel(citationText: String? = nil, errorMessage: String? = nil) -> String {
        guard citationText != nil || errorMessage != nil else {
            return ""
        }

        if let error = errorMessage {
            return """
            <div class="error-panel">
                <div class="error-title">Error</div>
                <div class="error-message">\(escapeHTML(error))</div>
            </div>
            """
        }

        if let citation = citationText {
            return """
            <div class="citation-panel">
                <div class="citation-header">
                    <span class="citation-title">Citation</span>
                    <button id="copyBtn" class="copy-button" onclick="copyCitation()">Copy</button>
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
        if let comparisonResult {
            let rows = FamilyComparisonReviewDetector.displayRows(for: comparisonResult.rows).map { displayRow in
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
            rowsHTML = "<tr><td colspan=\"5\">Comparison has not run.</td></tr>"
        }

        return """
        <div class="comparison-panel">
            <div class="comparison-header">
                <div>
                    <div class="comparison-title">Children Comparison</div>
                    <div class="comparison-couple">\(escapeHTML(coupleHeader))</div>
                </div>
            </div>
            \(extractionSummary)
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
        """
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
        .family-content {
            background: #fefdf8;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            font-size: 16px;
            white-space: pre-wrap;
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
        .comparison-couple, .fs-debug-summary {
            color: #666;
            font-size: 13px;
            margin-top: 4px;
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
        let navBar = renderNavigationBar(homeId: homeId, displayedId: family.familyId)
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
        let reviewQueueHTML = renderWorkupReviewQueue(workup.actions)
        let actionSectionsHTML = renderWorkupActionSections(workup.actions)
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

    private static func renderWorkupReviewQueue(_ actions: [FamilyWorkup.ActionSummary]) -> String {
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

        return """
        <section class="workup-section" id="review-queue">
            <h2>Review Queue</h2>
            <p class="workup-muted">\(actions.count) queued \(actions.count == 1 ? "action" : "actions") for collaborative review.</p>
            <nav class="workup-review-nav">
                \(links)
            </nav>
        </section>
        """
    }

    private static func renderWorkupActionSections(_ actions: [FamilyWorkup.ActionSummary]) -> String {
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
                actions: mismatches
            ),
            renderWorkupActionSection(
                id: "source-updates",
                title: "Source Updates",
                actions: sourceUpdates
            ),
            renderWorkupActionSection(
                id: "other-actions",
                title: "Other Actions",
                actions: otherActions
            )
        ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func renderWorkupActionSection(
        id: String,
        title: String,
        actions: [FamilyWorkup.ActionSummary]
    ) -> String {
        guard !actions.isEmpty else {
            return ""
        }

        return """
        <section class="workup-section" id="\(id)">
            <h2>\(escapeHTML(title))</h2>
            <ul>\(actions.map(renderWorkupAction).joined(separator: "\n"))</ul>
        </section>
        """
    }

    private static func renderWorkupAction(_ action: FamilyWorkup.ActionSummary) -> String {
        let personHTML = action.personName.map { " - \(escapeHTML($0))" } ?? ""
        let approvalHTML = action.approvalPrompt.map {
            "<div class=\"workup-action-prompt\">\(escapeHTML($0))</div>"
        } ?? ""
        let contextHTML = action.context.map(renderWorkupActionContext) ?? ""
        let sourceEditCommandHTML = renderSourceEditCommands(action)

        return """
        <li>
            <strong>\(escapeHTML(action.type))</strong>: \(escapeHTML(action.label))\(personHTML)
            <div class="workup-action-copy-row">
                <code class="workup-action-id">\(escapeHTML(action.id))</code>
                <button type="button" class="workup-copy-button" data-copy="\(escapeHTML(action.id))" onclick="copyWorkupValue(this)">Copy ID</button>
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

        function openHiskiChildResults(url) {
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

#endif // os(macOS)
