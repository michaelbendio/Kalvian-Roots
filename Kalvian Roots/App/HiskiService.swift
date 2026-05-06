//
//  HiskiService.swift
//  Kalvian Roots
//
//  Queries hiski.genealogia.fi using WKWebView for record pages
//  Extracts citation URLs automatically using JavaScript
//
//  Created by Michael Bendio on 10/20/25.
//

import Foundation
import SwiftUI
import Combine
#if os(macOS)
import AppKit
import WebKit
#endif

// MARK: - Error Types

enum HiskiServiceError: Error {
    case sessionFailed
    case invalidDate
    case urlCreationFailed
    case browserOpenFailed
    case noRecordFound
    case citationExtractionFailed
}

// MARK: - Extraction Mode

enum HiskiExtractionMode {
    case webView     // Use WKWebView for interactive extraction (SwiftUI app)
    case httpOnly    // Use pure HTTP for headless extraction (server)
}

// MARK: - WebView Window Manager with JavaScript Citation Extraction

#if os(macOS)
class HiskiWebViewManager: NSObject, WKNavigationDelegate {
    @MainActor static let shared = HiskiWebViewManager()
    
    @MainActor private var recordWindow: NSWindow?  // ← Back to strong reference, no delegate
    @MainActor private var recordWebView: WKWebView?
    @MainActor private var citationContinuation: CheckedContinuation<String, Error>?
    
    private let recordWindowX: CGFloat = 1300
    private let recordWindowY: CGFloat = 250
    private let recordWindowWidth: CGFloat = 1200
    private let recordWindowHeight: CGFloat = 450
    
    @MainActor private override init() {
        super.init()
    }
    
    /// Load record page and extract citation URL using JavaScript
    @MainActor func loadRecordAndExtractCitation(url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.citationContinuation = continuation

            // Create webView + window only once; reuse for subsequent queries
            if recordWebView == nil {
                let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: recordWindowWidth, height: recordWindowHeight))
                webView.navigationDelegate = self
                webView.allowsBackForwardNavigationGestures = true
                self.recordWebView = webView

                let window = NSWindow(
                    contentRect: NSRect(x: recordWindowX, y: recordWindowY, width: recordWindowWidth, height: recordWindowHeight),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                window.title = "Hiski Record"
                window.contentView = webView
                window.level = .floating
                self.recordWindow = window
            }

            // Bring window forward and load new URL into existing webView
            recordWindow?.makeKeyAndOrderFront(nil)
            recordWebView?.load(URLRequest(url: url))
            logInfo(.app, "🪟 Opened Hiski record window")
        }
    }
    
    @MainActor func closeRecordWindow() {
        recordWebView?.navigationDelegate = nil
        recordWebView = nil
        recordWindow?.close()
        recordWindow = nil
        logInfo(.app, "🪟 Closed Hiski record window")
    }
    
    @MainActor func closeAllWindows() {
        closeRecordWindow()
    }
    
    // Called when page finishes loading
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            logInfo(.app, "✅ Hiski record page loaded")
            
            // Extract citation URL using JavaScript
            let script = """
            (function() {
                // Find the "Link to this event" link
                var links = document.getElementsByTagName('a');
                for (var i = 0; i < links.length; i++) {
                    var href = links[i].getAttribute('href');
                    if (href && href.includes('+t')) {
                        return 'https://hiski.genealogia.fi' + href;
                    }
                }
                return null;
            })();
            """
            
            webView.evaluateJavaScript(script) { [weak self] result, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        logError(.app, "❌ JavaScript error: \(error.localizedDescription)")
                        self.citationContinuation?.resume(throwing: HiskiServiceError.citationExtractionFailed)
                        self.citationContinuation = nil
                        return
                    }
                    
                    if let citationUrl = result as? String, !citationUrl.isEmpty {
                        logInfo(.app, "📋 Extracted citation URL: \(citationUrl)")
                        self.citationContinuation?.resume(returning: citationUrl)
                        self.citationContinuation = nil
                    } else {
                        logError(.app, "❌ Could not find citation URL in page")
                        self.citationContinuation?.resume(throwing: HiskiServiceError.citationExtractionFailed)
                        self.citationContinuation = nil
                    }
                }
            }
        }
    }
    
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logError(.app, "❌ WebView failed to load: \(error.localizedDescription)")
            citationContinuation?.resume(throwing: error)
            citationContinuation = nil
        }
    }
}
#elseif os(iOS)
import SafariServices

@MainActor
class HiskiWebViewManager {
    static let shared = HiskiWebViewManager()
    private var presentingViewController: UIViewController?
    
    private init() {}
    
    func setPresentingViewController(_ viewController: UIViewController) {
        self.presentingViewController = viewController
    }
    
    func loadRecordAndExtractCitation(url: URL) async throws -> String {
        // On iOS, we can't extract from Safari, so just open it and return the URL
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                logInfo(.app, "📱 Opened Hiski record in Safari")
            } else {
                logError(.app, "Failed to open record URL in Safari")
            }
        }
        
        // For iOS, we'll need manual extraction
        // Return a placeholder that indicates manual extraction needed
        throw HiskiServiceError.citationExtractionFailed
    }
    
    func closeRecordWindow() {
        // Safari manages its own tabs - nothing to do
    }
    
    func closeAllWindows() {
        // Safari manages its own tabs - nothing to do
    }
}
#endif

// MARK: - Hiski Service

class HiskiService {
    static let yearsBeforeMarriage = 1
    static let childbearingWindowYears = 36
    static let maxHiskiResults = 50

    struct HiskiFamilyBirthRow: Equatable {
        let birthDate: String
        let childName: String
        let fatherName: String
        let motherName: String
        let recordPath: String
    }

    struct FamilyBirthSearchRequest: Equatable {
        let label: String
        let url: URL
    }

    struct HiskiFamilyBirthEvent: Equatable {
        let birthDate: String
        let childName: String
        let fatherName: String
        let motherName: String
        let recordURL: String
        let citationURL: String
    }

    private let nameEquivalenceManager: NameEquivalenceManager
    private let parishes = "0053,0093,0165,0183,0218,0172,0265,0295,0301,0386,0555,0581,0614"
    private var currentFamilyId: String?
    
    init(nameEquivalenceManager: NameEquivalenceManager) {
        self.nameEquivalenceManager = nameEquivalenceManager
    }
    
    func setCurrentFamily(_ familyId: String) {
        self.currentFamilyId = familyId
    }
    
    // MARK: - Query Methods with Result Type (Supporting both extraction modes)

    /**
     * Query death record and return result abstraction
     */
    func queryDeathWithResult(name: String, date: String, mode: HiskiExtractionMode = .webView) async -> HiskiQueryResult {
        do {
            let swedishName = normalizeForHiskiQuery(name)
            let firstName = swedishName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishName
            let formattedDate = formatDateForHiski(date)

            logInfo(.app, "🔍 Hiski Death Query (mode: \(mode)):")
            logInfo(.app, "  Name: \(firstName)")
            logInfo(.app, "  Date: \(formattedDate)")

            // Build search URL
            let searchUrl = try buildDeathSearchUrl(name: firstName, date: formattedDate)

            // Fetch search results HTML
            let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
            guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
                return .error(message: "Failed to fetch search results")
            }

            // Find matching record URL from HTML
            guard let recordPath = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
                logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
                return .notFound
            }

            logInfo(.app, "✅ Found matching record path: \(recordPath)")

            // Load record page and extract citation
            let recordUrl = "https://hiski.genealogia.fi" + recordPath

            let citationUrl: String
            switch mode {
            case .webView:
                #if os(macOS)
                guard let url = URL(string: recordUrl) else {
                    return .error(message: "Invalid record URL")
                }
                citationUrl = try await HiskiWebViewManager.shared.loadRecordAndExtractCitation(url: url)
                #else
                return .error(message: "WebView extraction not supported on iOS")
                #endif
            case .httpOnly:
                citationUrl = try await loadRecordAndExtractCitationHTTP(recordUrl: recordUrl)
            }

            return .found(citationURL: citationUrl, recordURL: recordUrl)

        } catch {
            logError(.app, "❌ Hiski query failed: \(error.localizedDescription)")
            return .error(message: error.localizedDescription)
        }
    }

    /**
     * Query birth record and return result abstraction
     */
    func queryBirthWithResult(name: String, date: String, fatherName: String? = nil, mode: HiskiExtractionMode = .webView) async -> HiskiQueryResult {
        do {
            let swedishName = normalizeForHiskiQuery(name)
            let firstName = swedishName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishName

            var fatherFirstName: String? = nil
            if let father = fatherName {
                let swedishFather = normalizeForHiskiQuery(father)
                fatherFirstName = swedishFather.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let formattedDate = formatDateForHiski(date)

            logInfo(.app, "🔍 Hiski Birth Query (mode: \(mode)):")
            logInfo(.app, "  Name: \(firstName)")
            logInfo(.app, "  Father: \(fatherFirstName ?? "unknown")")
            logInfo(.app, "  Date: \(formattedDate)")

            // Build search URL
            let searchUrl = try buildBirthSearchUrl(name: firstName, date: formattedDate, fatherName: fatherFirstName)

            // Fetch search results HTML
            let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
            guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
                return .error(message: "Failed to fetch search results")
            }

            // Find matching record URL
            guard let recordPath = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
                logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
                return .notFound
            }

            logInfo(.app, "✅ Found matching record path: \(recordPath)")

            // Load record page and extract citation
            let recordUrl = "https://hiski.genealogia.fi" + recordPath

            let citationUrl: String
            switch mode {
            case .webView:
                #if os(macOS)
                guard let url = URL(string: recordUrl) else {
                    return .error(message: "Invalid record URL")
                }
                citationUrl = try await HiskiWebViewManager.shared.loadRecordAndExtractCitation(url: url)
                #else
                return .error(message: "WebView extraction not supported on iOS")
                #endif
            case .httpOnly:
                citationUrl = try await loadRecordAndExtractCitationHTTP(recordUrl: recordUrl)
            }

            return .found(citationURL: citationUrl, recordURL: recordUrl)

        } catch {
            logError(.app, "❌ Hiski query failed: \(error.localizedDescription)")
            return .error(message: error.localizedDescription)
        }
    }

    /**
     * Query marriage record and return result abstraction
     */
    func queryMarriageWithResult(husbandName: String, wifeName: String, date: String, mode: HiskiExtractionMode = .webView) async -> HiskiQueryResult {
        do {
            let swedishHusband = normalizeForHiskiQuery(husbandName)
            let swedishWife = normalizeForHiskiQuery(wifeName)

            let husbandFirst = swedishHusband.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishHusband
            let wifeFirst = swedishWife.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishWife

            let formattedDate = formatDateForHiski(date)

            logInfo(.app, "🔍 Hiski Marriage Query (mode: \(mode)):")
            logInfo(.app, "  Husband: \(husbandFirst)")
            logInfo(.app, "  Wife: \(wifeFirst)")
            logInfo(.app, "  Date: \(formattedDate)")

            // Build search URL
            let searchUrl = try buildMarriageSearchUrl(husbandName: husbandFirst, wifeName: wifeFirst, date: formattedDate)

            // Fetch search results
            let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
            guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
                return .error(message: "Failed to fetch search results")
            }

            // Find matching record
            guard let recordPath = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
                logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
                return .notFound
            }

            logInfo(.app, "✅ Found matching record path: \(recordPath)")

            // Load record page and extract citation
            let recordUrl = "https://hiski.genealogia.fi" + recordPath

            let citationUrl: String
            switch mode {
            case .webView:
                #if os(macOS)
                guard let url = URL(string: recordUrl) else {
                    return .error(message: "Invalid record URL")
                }
                citationUrl = try await HiskiWebViewManager.shared.loadRecordAndExtractCitation(url: url)
                #else
                return .error(message: "WebView extraction not supported on iOS")
                #endif
            case .httpOnly:
                citationUrl = try await loadRecordAndExtractCitationHTTP(recordUrl: recordUrl)
            }

            return .found(citationURL: citationUrl, recordURL: recordUrl)

        } catch {
            logError(.app, "❌ Hiski query failed: \(error.localizedDescription)")
            return .error(message: error.localizedDescription)
        }
    }

    // MARK: - Query Methods (using WKWebView for record pages)
    
    func queryDeath(name: String, date: String) async throws -> HiskiCitation {
        let swedishName = normalizeForHiskiQuery(name)
        let firstName = swedishName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishName
        let formattedDate = formatDateForHiski(date)
        
        logInfo(.app, "🔍 Hiski Death Query:")
        logInfo(.app, "  Name: \(firstName)")
        logInfo(.app, "  Date: \(formattedDate)")
        
        // Build search URL
        let searchUrl = try buildDeathSearchUrl(name: firstName, date: formattedDate)
        
        // Fetch search results HTML
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Find matching record URL from HTML
        guard let recordPath = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
            logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "✅ Found matching record path: \(recordPath)")
        
        // Load record page in WKWebView and extract citation with JavaScript
        let recordUrl = "https://hiski.genealogia.fi" + recordPath
        guard let url = URL(string: recordUrl) else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        logInfo(.app, "🌐 Loading record page in WebView: \(recordUrl)")
        let citationUrl = try await HiskiWebViewManager.shared.loadRecordAndExtractCitation(url: url)
        
        logInfo(.app, "✅ Citation extracted: \(citationUrl)")
        
        // Extract record ID from citation URL
        let recordId = citationUrl.components(separatedBy: "+t").last ?? "UNKNOWN"
        
        return HiskiCitation(
            recordType: .death,
            personName: name,
            date: date,
            url: citationUrl,
            recordId: recordId,
            spouse: nil
        )
    }
    
    func queryBirth(name: String, date: String, fatherName: String? = nil) async throws -> HiskiCitation {
        let swedishName = normalizeForHiskiQuery(name)
        let firstName = swedishName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishName
        
        var fatherFirstName: String? = nil
        if let father = fatherName {
            let swedishFather = normalizeForHiskiQuery(father)
            fatherFirstName = swedishFather.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let formattedDate = formatDateForHiski(date)
        
        logInfo(.app, "🔍 Hiski Birth Query:")
        logInfo(.app, "  Name: \(firstName)")
        logInfo(.app, "  Date: \(formattedDate)")
        if let father = fatherFirstName {
            logInfo(.app, "  Father: \(father)")
        }
        
        // Build search URL
        let searchUrl = try buildBirthSearchUrl(name: firstName, date: formattedDate, fatherName: fatherFirstName)
        
        // Fetch search results HTML
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Find matching record URL
        guard let recordPath = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
            logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "✅ Found matching record path: \(recordPath)")
        
        // Load in WKWebView and extract citation
        let recordUrl = "https://hiski.genealogia.fi" + recordPath
        guard let url = URL(string: recordUrl) else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        logInfo(.app, "🌐 Loading record page in WebView: \(recordUrl)")
        let citationUrl = try await HiskiWebViewManager.shared.loadRecordAndExtractCitation(url: url)
        
        logInfo(.app, "✅ Citation extracted: \(citationUrl)")
        
        let recordId = citationUrl.components(separatedBy: "+t").last ?? "UNKNOWN"
        
        return HiskiCitation(
            recordType: .birth,
            personName: name,
            date: date,
            url: citationUrl,
            recordId: recordId,
            spouse: nil
        )
    }
    
    func queryMarriage(husbandName: String, wifeName: String, date: String) async throws -> HiskiCitation {
        let swedishHusband = normalizeForHiskiQuery(husbandName)
        let swedishWife = normalizeForHiskiQuery(wifeName)
        
        let husbandFirst = swedishHusband.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishHusband
        let wifeFirst = swedishWife.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishWife
        
        let formattedDate = formatDateForHiski(date)
        
        logInfo(.app, "🔍 Hiski Marriage Query:")
        logInfo(.app, "  Husband: \(husbandFirst)")
        logInfo(.app, "  Wife: \(wifeFirst)")
        logInfo(.app, "  Date: \(formattedDate)")
        
        // Build search URL
        let searchUrl = try buildMarriageSearchUrl(husbandName: husbandFirst, wifeName: wifeFirst, date: formattedDate)
        
        // Fetch search results
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Find matching record
        guard let recordPath = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
            logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "✅ Found matching record path: \(recordPath)")
        
        // Load in WKWebView and extract citation
        let recordUrl = "https://hiski.genealogia.fi" + recordPath
        guard let url = URL(string: recordUrl) else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        logInfo(.app, "🌐 Loading record page in WebView: \(recordUrl)")
        let citationUrl = try await HiskiWebViewManager.shared.loadRecordAndExtractCitation(url: url)
        
        logInfo(.app, "✅ Citation extracted: \(citationUrl)")
        
        let recordId = citationUrl.components(separatedBy: "+t").last ?? "UNKNOWN"
        
        return HiskiCitation(
            recordType: .marriage,
            personName: husbandName,
            date: date,
            url: citationUrl,
            recordId: recordId,
            spouse: wifeName
        )
    }
    
    // MARK: - HTML Parsing (matching hiski.py algorithm)
    
    private func findMatchingRecordUrl(from html: String, queryDate: String) -> String? {
        // Confirm results exist via <LI>Years line
        let yearsPattern = "<LI>\\s*Years\\s+([0-9.]+)\\s*-\\s*([0-9.]+)"
        guard let yearsRegex = try? NSRegularExpression(pattern: yearsPattern, options: [.caseInsensitive]),
              yearsRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil else {
            logWarn(.app, "⚠️ Could not find <LI>Years line in search results")
            return nil
        }

        logInfo(.app, "📅 Looking for record with date: \(queryDate)")

        // Parse row by row — find a <TR> containing both sl.gif and the query date.
        // Marriage records have sl.gif in Announc. column and date in Married column (separate <TD>s).
        // Birth/death records have sl.gif and date adjacent in the same cell.
        // Row-level matching handles both cases.
        let rowPattern = "<TR[^>]*>(.*?)</TR>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let rows = rowRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for rowMatch in rows {
            guard let rowRange = Range(rowMatch.range(at: 1), in: html) else { continue }
            let rowContent = String(html[rowRange])

            guard rowContent.contains(queryDate) else { continue }

            if let href = extractSlGifHref(from: rowContent) {
                logInfo(.app, "✅ Found matching link in row: \(href)")
                return href
            }
        }

        logWarn(.app, "⚠️ No sl.gif link found matching date \(queryDate)")
        return nil
    }

    func parseFamilyBirthResultsTable(_ html: String) -> [HiskiFamilyBirthRow] {
        extractTableRows(from: html).compactMap(parseFamilyBirthRow)
    }

    func fetchCitationsForFamilyBirthRows(_ rows: [HiskiFamilyBirthRow]) async throws -> [HiskiFamilyBirthEvent] {
        try await fetchCitationsForFamilyBirthRows(rows) { recordUrl in
            try await self.loadRecordAndExtractCitationHTTP(recordUrl: recordUrl)
        }
    }

    func fetchCitationsForFamilyBirthRows(
        _ rows: [HiskiFamilyBirthRow],
        using citationLoader: (String) async throws -> String
    ) async throws -> [HiskiFamilyBirthEvent] {
        guard !rows.isEmpty else {
            return []
        }

        var events: [HiskiFamilyBirthEvent] = []
        events.reserveCapacity(rows.count)

        for row in rows {
            let recordURL = "https://hiski.genealogia.fi" + row.recordPath
            let citationURL = try await citationLoader(recordURL)

            events.append(
                HiskiFamilyBirthEvent(
                    birthDate: row.birthDate,
                    childName: row.childName,
                    fatherName: row.fatherName,
                    motherName: row.motherName,
                    recordURL: recordURL,
                    citationURL: citationURL
                )
            )
        }

        return events
    }
    
    // MARK: - Pure HTTP Citation Extraction

    /**
     * Extract citation URL from record page HTML using regex (pure HTTP mode)
     * This replicates the logic from the Python script hiski.py
     */
    private func extractCitationUrlFromHtml(_ html: String) -> String? {
        // Pattern to find citation links with +t in the href
        // Example: HREF="/hiski?en+t4086417"
        let pattern = "HREF=\"(/hiski\\?en\\+t\\d+)\""

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let hrefRange = Range(match.range(at: 1), in: html) else {
            logWarn(.app, "⚠️ Could not find citation link in record page HTML")
            return nil
        }

        let citationPath = String(html[hrefRange])
        let citationUrl = "https://hiski.genealogia.fi" + citationPath
        logInfo(.app, "📋 Extracted citation URL from HTML: \(citationUrl)")

        return citationUrl
    }

    /**
     * Load record page and extract citation URL using pure HTTP
     */
    private func loadRecordAndExtractCitationHTTP(recordUrl: String) async throws -> String {
        guard let url = URL(string: recordUrl) else {
            throw HiskiServiceError.urlCreationFailed
        }

        // Fetch the record page HTML
        let (recordData, _) = try await URLSession.shared.data(from: url)
        guard let recordHtml = String(data: recordData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }

        // Extract citation URL from HTML
        guard let citationUrl = extractCitationUrlFromHtml(recordHtml) else {
            throw HiskiServiceError.citationExtractionFailed
        }

        return citationUrl
    }

    private func parseFamilyBirthRow(from rowHtml: String) -> HiskiFamilyBirthRow? {
        guard let recordPath = extractSlGifHref(from: rowHtml) else {
            return nil
        }

        let cleanedCellTexts = extractTableCellContents(from: rowHtml).map(cleanHiskiCellText)
        guard !cleanedCellTexts.isEmpty else {
            return nil
        }

        let dateCandidates = Array(cleanedCellTexts.prefix(2))
        guard let birthDate = dateCandidates.compactMap(extractBirthDate).first else {
            return nil
        }

        let trailingValues = cleanedCellTexts.filter { !$0.isEmpty }.suffix(3)
        guard trailingValues.count == 3 else {
            return nil
        }

        let names = Array(trailingValues)
        let fatherName = names[0]
        let motherName = names[1]
        let childName = names[2]

        guard !fatherName.isEmpty, !motherName.isEmpty, !childName.isEmpty else {
            return nil
        }

        return HiskiFamilyBirthRow(
            birthDate: birthDate,
            childName: childName,
            fatherName: fatherName,
            motherName: motherName,
            recordPath: recordPath
        )
    }

    private func extractTableRows(from html: String) -> [String] {
        let rowStartPattern = "<TR[^>]*>"
        guard let rowStartRegex = try? NSRegularExpression(
            pattern: rowStartPattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let matches = rowStartRegex.matches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        )
        guard !matches.isEmpty else { return [] }

        var rows: [String] = []

        for i in matches.indices {
            guard let startRange = Range(matches[i].range, in: html) else { continue }
            let rowStart = startRange.lowerBound

            var candidateEnds: [String.Index] = []

            if i + 1 < matches.count,
               let nextRange = Range(matches[i + 1].range, in: html) {
                candidateEnds.append(nextRange.lowerBound)
            }

            if let rowCloseRange = html.range(
                of: "</TR>",
                options: [.caseInsensitive],
                range: rowStart..<html.endIndex
            ) {
                candidateEnds.append(rowCloseRange.lowerBound)
            }

            if let tableEndRange = html.range(
                of: "</TABLE>",
                options: [.caseInsensitive],
                range: rowStart..<html.endIndex
            ) {
                candidateEnds.append(tableEndRange.lowerBound)
            }

            if let brRange = html.range(
                of: "<BR",
                options: [.caseInsensitive],
                range: rowStart..<html.endIndex
            ) {
                candidateEnds.append(brRange.lowerBound)
            }

            let rowEnd = candidateEnds.min() ?? html.endIndex
            rows.append(String(html[rowStart..<rowEnd]))
        }

        return rows
    }
    
    private func extractSlGifHref(from html: String) -> String? {
        let pattern = "<a\\s+href=\"([^\"]+)\">\\s*<img[^>]+src=\"/historia/sl\\.gif\""

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let hrefRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[hrefRange])
    }

    private func extractTableCellContents(from html: String) -> [String] {
        let delimiter = "\u{1F}"

        let tdSeparated = html.replacingOccurrences(
            of: "(?i)<td[^>]*>",
            with: delimiter,
            options: .regularExpression
        )

        return Array(tdSeparated.components(separatedBy: delimiter).dropFirst())
    }
    
    private func cleanHiskiCellText(_ html: String) -> String {
        let withoutSmallNotes = html.replacingOccurrences(
            of: "(?is)<small[^>]*>.*?</small>",
            with: " ",
            options: .regularExpression
        )

        let textWithoutTags = withoutSmallNotes.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        let decodedText = textWithoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        let normalizedWhitespace = decodedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalizedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractBirthDate(from text: String) -> String? {
        let pattern = "\\b\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}\\b|\\b\\d{4}\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let dateRange = Range(match.range, in: text) else {
            return nil
        }

        return String(text[dateRange])
    }

    // MARK: - URL Building

    private func buildBirthSearchUrl(name: String, date: String, fatherName: String? = nil) throws -> URL {
        var params = [
            "komento": "haku",
            "srk": parishes,
            "kirja": "kastetut",
            "kieli": "en",
            "etunimi": name,
            "alkuvuosi": date,
            "loppuvuosi": date,
            "ikyla": "",
            "maxkpl": String(Self.maxHiskiResults),
            "ietunimi": "",
            "aetunimi": "",
            "ipatronyymi": "",
            "apatronyymi": "",
            "isukunimi": "",
            "asukunimi": "",
            "iammatti": "",
            "aammatti": "",
            "ketunimi": "",
            "kpatronyymi": "",
            "ksukunimi": "",
            "kammatti": ""
        ]
        
        if let fatherFirst = fatherName, !fatherFirst.isEmpty {
            params["ietunimi"] = fatherFirst
        }
        
        return try buildSearchUrl(params: params)
    }

    func buildFamilyBirthSearchUrl(
        fatherName: String,
        fatherPatronymic: String?,
        motherName: String,
        motherPatronymic: String?,
        marriageYear: Int
    ) throws -> URL {
        try makeFamilyBirthSearchUrl(
            fatherName: normalizeForHiskiQuery(fatherName),
            fatherPatronymic: hiskiPatronymicSearchInput(for: fatherPatronymic),
            motherName: normalizeForHiskiQuery(motherName),
            motherPatronymic: hiskiPatronymicSearchInput(for: motherPatronymic),
            marriageYear: marriageYear
        )
    }

    func buildFamilyBirthSearchRequests(
        fatherName: String,
        fatherPatronymic: String?,
        motherName: String,
        motherPatronymic: String?,
        marriageYear: Int
    ) throws -> [FamilyBirthSearchRequest] {
        var requests: [FamilyBirthSearchRequest] = []
        var seenURLs: Set<String> = []

        func appendRequest(
            label: String,
            fatherSearchName: String,
            fatherSearchPatronymic: String?,
            motherSearchName: String,
            motherSearchPatronymic: String?
        ) throws {
            let url = try makeFamilyBirthSearchUrl(
                fatherName: fatherSearchName,
                fatherPatronymic: fatherSearchPatronymic,
                motherName: motherSearchName,
                motherPatronymic: motherSearchPatronymic,
                marriageYear: marriageYear
            )

            guard seenURLs.insert(url.absoluteString).inserted else {
                return
            }

            requests.append(FamilyBirthSearchRequest(label: label, url: url))
        }

        let hiskiFatherName = normalizeForHiskiQuery(fatherName)
        let hiskiMotherName = normalizeForHiskiQuery(motherName)
        let hiskiFatherPatronymic = hiskiPatronymicSearchInput(for: fatherPatronymic)
        let hiskiMotherPatronymic = hiskiPatronymicSearchInput(for: motherPatronymic)

        try appendRequest(
            label: "primary HisKi parent query",
            fatherSearchName: hiskiFatherName,
            fatherSearchPatronymic: hiskiFatherPatronymic,
            motherSearchName: hiskiMotherName,
            motherSearchPatronymic: hiskiMotherPatronymic
        )

        try appendRequest(
            label: "exact Juuret parent names fallback",
            fatherSearchName: fatherName,
            fatherSearchPatronymic: fatherPatronymic,
            motherSearchName: motherName,
            motherSearchPatronymic: motherPatronymic
        )

        return requests
    }

    private func makeFamilyBirthSearchUrl(
        fatherName: String,
        fatherPatronymic: String?,
        motherName: String,
        motherPatronymic: String?,
        marriageYear: Int
    ) throws -> URL {
        let startYear = marriageYear - Self.yearsBeforeMarriage
        let endYear = marriageYear + Self.childbearingWindowYears

        let params = [
            "komento": "haku",
            "srk": parishes,
            "kirja": "kastetut",
            "kieli": "en",
            "etunimi": "",
            "alkuvuosi": String(startYear),
            "loppuvuosi": String(endYear),
            "ikyla": "",
            "maxkpl": String(Self.maxHiskiResults),
            "ietunimi": fatherName,
            "aetunimi": motherName,
            "ipatronyymi": fatherPatronymic ?? "",
            "apatronyymi": motherPatronymic ?? "",
            "isukunimi": "",
            "asukunimi": "",
            "iammatti": "",
            "aammatti": "",
            "ketunimi": "",
            "kpatronyymi": "",
            "ksukunimi": "",
            "kammatti": ""
        ]

        return try buildSearchUrl(params: params)
    }
    
    private func buildDeathSearchUrl(name: String, date: String) throws -> URL {
        let params = [
            "komento": "haku",
            "srk": parishes,
            "kirja": "haudatut",
            "kieli": "en",
            "alkuvuosi": date,
            "loppuvuosi": date,
            "maxkpl": String(Self.maxHiskiResults),
            "ietunimi": name,
            "aetunimi": "",
            "ipatronyymi": "",
            "apatronyymi": "",
            "isukunimi": "",
            "asukunimi": "",
            "iammatti": "",
            "aammatti": "",
            "ikyla": "",
            "ssuhde": "ei+v%E4li%E4",
            "ksyy": "",
            "syntalku": "",
            "syntloppu": "",
            "ika": ""
        ]
        
        return try buildSearchUrl(params: params)
    }
    
    private func buildMarriageSearchUrl(husbandName: String, wifeName: String, date: String) throws -> URL {
        let params = [
            "komento": "haku",
            "srk": parishes,
            "kirja": "vihityt",
            "kieli": "en",
            "alkuvuosi": date,
            "loppuvuosi": date,
            "maxkpl": String(Self.maxHiskiResults),
            "ietunimi": husbandName,
            "aetunimi": wifeName,
            "ipatronyymi": "",
            "apatronyymi": "",
            "isukunimi": "",
            "asukunimi": "",
            "iammatti": "",
            "aammatti": "",
            "ikyla": "",
            "akyla": ""
        ]
        
        return try buildSearchUrl(params: params)
    }
    
    private func buildSearchUrl(params: [String: String]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hiski.genealogia.fi"
        components.path = "/hiski"
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = components.url else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        return url
    }
    
    // MARK: - HisKi Query Normalization

    private func normalizeForHiskiQuery(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        var parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let firstPart = parts.first,
              let override = hiskiGivenNameOverride(for: firstPart) else {
            return trimmed
        }

        parts[0] = override
        let normalized = parts.joined(separator: " ")
        logInfo(.app, "✅ HisKi query override '\(trimmed)' → '\(normalized)'")
        return normalized
    }

    private func hiskiGivenNameOverride(for name: String) -> String? {
        // HisKi already handles most Finnish/Swedish equivalents; these are only known query exceptions.
        switch normalizedHiskiLookupToken(name) {
        case "malin":
            return "Magdalena"
        case "pietari":
            return "Per"
        default:
            return nil
        }
    }

    private func hiskiPatronymicSearchInput(for patronymic: String?) -> String? {
        guard let patronymic else {
            return nil
        }

        let cleaned = patronymic.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )

        guard !cleaned.isEmpty else {
            return nil
        }

        if let override = hiskiPatronymicOverride(for: cleaned) {
            logInfo(.app, "✅ HisKi patronymic override '\(cleaned)' → '\(override)'")
            return override
        }

        return cleaned
    }

    private func hiskiPatronymicOverride(for patronymic: String) -> String? {
        // HisKi already handles most patronymic variants; these Pietari-derived forms need explicit query terms.
        switch normalizedHiskiLookupToken(patronymic) {
        case "pietarinp":
            return "Perss"
        case "pietarint", "pietarintytar":
            return "Persdr"
        default:
            return nil
        }
    }

    private func normalizedHiskiLookupToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }
    
    // MARK: - Date Formatting
    
    private func formatDateForHiski(_ dateString: String, parentBirthYear: Int? = nil) -> String {
        var cleaned = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleaned.contains(".") {
            let components = cleaned.components(separatedBy: ".")
            if components.count == 3 {
                let day = String(Int(components[0]) ?? 0)
                let month = String(Int(components[1]) ?? 0)
                var year = components[2]
                
                // If 2-digit year, expand using CitationGenerator's logic
                if year.count == 2, let twoDigitYear = Int(year) {
                    let fullYear = CitationGenerator.inferCentury(for: twoDigitYear, parentBirthYear: parentBirthYear)
                    year = String(fullYear)
                }
                
                return "\(day).\(month).\(year)"
            }
        }
        
        return cleaned
    }
}
