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
class HiskiWebViewManager: NSObject, WKNavigationDelegate, NSWindowDelegate {
    @MainActor static let shared = HiskiWebViewManager()
    
    @MainActor private var recordWindow: NSWindow?
    @MainActor private var recordWebView: WKWebView?
    @MainActor private var searchResultsWindow: NSWindow?
    @MainActor private var searchResultsWebView: WKWebView?
    @MainActor private var citationContinuation: CheckedContinuation<String, Error>?
    
    private let recordWindowX: CGFloat = 1300
    private let recordWindowY: CGFloat = 250
    private let recordWindowWidth: CGFloat = 650
    private let recordWindowHeight: CGFloat = 430
    private let searchResultsWindowX: CGFloat = 500
    private let searchResultsWindowY: CGFloat = 180
    private let searchResultsWindowWidth: CGFloat = 900
    private let searchResultsWindowHeight: CGFloat = 650
    
    @MainActor private override init() {
        super.init()
    }
    
    /// Load record page and extract citation URL using JavaScript
    @MainActor func loadRecordAndExtractCitation(url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.citationContinuation?.resume(throwing: HiskiServiceError.citationExtractionFailed)
            self.citationContinuation = continuation

            let webView = ensureRecordWindow(title: "HisKi Record")

            // Bring window forward and load new URL into existing webView
            recordWindow?.makeKeyAndOrderFront(nil)
            webView.load(URLRequest(url: url))
            logInfo(.app, "🪟 Opened Hiski record window")
        }
    }

    /// Load a HisKi page for manual review without attempting citation extraction.
    @MainActor func loadSearchResults(url: URL) {
        let webView = ensureSearchResultsWindow()
        searchResultsWindow?.makeKeyAndOrderFront(nil)
        webView.load(URLRequest(url: url))
        logInfo(.app, "🪟 Opened Hiski results window")
    }

    @MainActor
    @discardableResult
    private func ensureRecordWindow(title: String = "HisKi Record") -> WKWebView {
        if let recordWebView, let recordWindow, recordWindow.isVisible {
            recordWindow.title = title
            return recordWebView
        }

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
        window.title = title
        window.contentView = webView
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.recordWindow = window

        return webView
    }

    @MainActor
    @discardableResult
    private func ensureSearchResultsWindow() -> WKWebView {
        if let searchResultsWebView, let searchResultsWindow, searchResultsWindow.isVisible {
            return searchResultsWebView
        }

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: searchResultsWindowWidth, height: searchResultsWindowHeight))
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        self.searchResultsWebView = webView

        let window = NSWindow(
            contentRect: NSRect(
                x: searchResultsWindowX,
                y: searchResultsWindowY,
                width: searchResultsWindowWidth,
                height: searchResultsWindowHeight
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HisKi Results"
        window.contentView = webView
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.searchResultsWindow = window

        return webView
    }
    
    @MainActor func closeRecordWindow() {
        let window = recordWindow
        clearRecordWindowState(resumePendingContinuation: true)
        window?.delegate = nil
        window?.close()
        recordWindow = nil
        logInfo(.app, "🪟 Closed Hiski record window")
    }

    @MainActor func closeSearchResultsWindow() {
        let window = searchResultsWindow
        clearSearchResultsWindowState()
        window?.delegate = nil
        window?.close()
        searchResultsWindow = nil
        logInfo(.app, "🪟 Closed Hiski results window")
    }
    
    @MainActor func closeAllWindows() {
        closeRecordWindow()
        closeSearchResultsWindow()
    }

    @MainActor func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === recordWindow {
            clearRecordWindowState(resumePendingContinuation: true)
            recordWindow = nil
            logInfo(.app, "🪟 Hiski record window closed by user")
        } else if notification.object as? NSWindow === searchResultsWindow {
            clearSearchResultsWindowState()
            searchResultsWindow = nil
            logInfo(.app, "🪟 Hiski results window closed by user")
        }
    }

    @MainActor
    private func clearRecordWindowState(resumePendingContinuation: Bool) {
        recordWebView?.navigationDelegate = nil
        recordWebView = nil

        if resumePendingContinuation {
            citationContinuation?.resume(throwing: HiskiServiceError.citationExtractionFailed)
            citationContinuation = nil
        }
    }

    @MainActor
    private func clearSearchResultsWindowState() {
        searchResultsWebView?.navigationDelegate = nil
        searchResultsWebView = nil
    }

    #if DEBUG
    @MainActor func debugPrepareRecordWindowForTests() {
        _ = ensureRecordWindow()
    }

    @MainActor func debugLoadSearchResultsForTests(url: URL) {
        loadSearchResults(url: url)
    }

    @MainActor func debugSimulateUserClosingRecordWindowForTests() {
        recordWindow?.close()
    }

    @MainActor var debugHasRecordWindowForTests: Bool {
        recordWindow != nil && recordWebView != nil
    }

    @MainActor var debugHasSearchResultsWindowForTests: Bool {
        searchResultsWindow != nil && searchResultsWebView != nil
    }

    @MainActor var debugRecordWindowContentSizeForTests: CGSize? {
        recordWindow?.contentView?.frame.size
    }

    @MainActor var debugRecordWindowTitleForTests: String? {
        recordWindow?.title
    }

    @MainActor var debugSearchResultsWindowTitleForTests: String? {
        searchResultsWindow?.title
    }
    #endif
    
    // Called when page finishes loading
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard webView === recordWebView, citationContinuation != nil else {
                logInfo(.app, "✅ Hiski page loaded")
                return
            }

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
            if webView === recordWebView, citationContinuation != nil {
                citationContinuation?.resume(throwing: error)
                citationContinuation = nil
            }
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

    func loadSearchResults(url: URL) {
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                logInfo(.app, "📱 Opened Hiski results in Safari")
            } else {
                logError(.app, "Failed to open Hiski results URL in Safari")
            }
        }
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
    static let childbearingWindowYears = 35
    static let maxHiskiResults = 50

    struct HiskiFamilyBirthRow: Equatable {
        let birthDate: String
        let childName: String
        let fatherName: String
        let motherName: String
        let recordPath: String
        let parish: String?
        let villageFarm: String?

        init(
            birthDate: String,
            childName: String,
            fatherName: String,
            motherName: String,
            recordPath: String,
            parish: String? = nil,
            villageFarm: String? = nil
        ) {
            self.birthDate = birthDate
            self.childName = childName
            self.fatherName = fatherName
            self.motherName = motherName
            self.recordPath = recordPath
            self.parish = parish
            self.villageFarm = villageFarm
        }
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
        let parish: String?
        let villageFarm: String?

        init(
            birthDate: String,
            childName: String,
            fatherName: String,
            motherName: String,
            recordURL: String,
            citationURL: String,
            parish: String? = nil,
            villageFarm: String? = nil
        ) {
            self.birthDate = birthDate
            self.childName = childName
            self.fatherName = fatherName
            self.motherName = motherName
            self.recordURL = recordURL
            self.citationURL = citationURL
            self.parish = parish
            self.villageFarm = villageFarm
        }
    }

    struct HiskiParentCoupleGroupKey: Hashable, Equatable {
        let parish: String
        let villageFarm: String
        let fatherNormalizedDisplayName: String
        let motherNormalizedDisplayName: String
    }

    struct HiskiFamilyBirthRowsFilterResult: Equatable {
        let rows: [HiskiFamilyBirthRow]
        let isAnchored: Bool
        let originalRowCount: Int
        let retainedGroupCount: Int

        var confidenceLabel: String {
            isAnchored ? "anchored" : "unanchored low-confidence"
        }
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

    func filterFamilyBirthRowsAnchoredToJuuretChildren(
        _ rows: [HiskiFamilyBirthRow],
        juuretChildren: [Person]
    ) -> HiskiFamilyBirthRowsFilterResult {
        let juuretBirthDates = Set(
            juuretChildren.compactMap { normalizedBirthDateKey($0.birthDate) }
        )

        guard !rows.isEmpty, !juuretBirthDates.isEmpty else {
            return HiskiFamilyBirthRowsFilterResult(
                rows: rows,
                isAnchored: false,
                originalRowCount: rows.count,
                retainedGroupCount: 0
            )
        }

        let groupedRows = Dictionary(grouping: rows, by: parentCoupleGroupKey(for:))
        let anchoredGroupKeys = Set(
            groupedRows.compactMap { key, groupRows in
                groupRows.contains { row in
                    guard let birthDate = normalizedBirthDateKey(row.birthDate) else {
                        return false
                    }

                    return juuretBirthDates.contains(birthDate)
                } ? key : nil
            }
        )

        guard !anchoredGroupKeys.isEmpty else {
            return HiskiFamilyBirthRowsFilterResult(
                rows: rows,
                isAnchored: false,
                originalRowCount: rows.count,
                retainedGroupCount: 0
            )
        }

        let filteredRows = rows.filter { row in
            anchoredGroupKeys.contains(parentCoupleGroupKey(for: row))
        }

        return HiskiFamilyBirthRowsFilterResult(
            rows: filteredRows,
            isAnchored: true,
            originalRowCount: rows.count,
            retainedGroupCount: anchoredGroupKeys.count
        )
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
                    citationURL: citationURL,
                    parish: row.parish,
                    villageFarm: row.villageFarm
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

        let trailingValues = cleanedCellTexts.enumerated()
            .filter { !$0.element.isEmpty }
            .suffix(3)
        guard trailingValues.count == 3 else {
            return nil
        }

        let names = Array(trailingValues)
        let fatherName = names[0].element
        let motherName = names[1].element
        let childName = names[2].element
        let fatherIndex = names[0].offset
        let locationValues = cleanedCellTexts.enumerated()
            .filter { index, value in
                index > 1 && index < fatherIndex && !value.isEmpty
            }
            .map(\.element)
        let parish = locationValues.first
        let joinedVillageFarm = locationValues.dropFirst().joined(separator: " / ")
        let villageFarm = joinedVillageFarm.isEmpty ? nil : joinedVillageFarm

        guard !fatherName.isEmpty, !motherName.isEmpty, !childName.isEmpty else {
            return nil
        }

        return HiskiFamilyBirthRow(
            birthDate: birthDate,
            childName: childName,
            fatherName: fatherName,
            motherName: motherName,
            recordPath: recordPath,
            parish: parish,
            villageFarm: villageFarm
        )
    }

    private func parentCoupleGroupKey(for row: HiskiFamilyBirthRow) -> HiskiParentCoupleGroupKey {
        HiskiParentCoupleGroupKey(
            parish: normalizedDisplayValue(row.parish),
            villageFarm: normalizedDisplayValue(row.villageFarm),
            fatherNormalizedDisplayName: normalizedParentDisplayName(row.fatherName),
            motherNormalizedDisplayName: normalizedParentDisplayName(row.motherName)
        )
    }

    private func normalizedBirthDateKey(_ rawDate: String?) -> String? {
        guard let rawDate else {
            return nil
        }

        let normalized = formatDateForHiski(rawDate)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedDisplayValue(_ rawValue: String?) -> String {
        rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current) ?? ""
    }

    private func normalizedParentDisplayName(_ rawName: String) -> String {
        let withoutTrailingAge = rawName.replacingOccurrences(
            of: "\\s+\\d{1,3}(?:-\\d{1,3})?$",
            with: "",
            options: .regularExpression
        )

        return normalizedDisplayValue(withoutTrailingAge)
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
        marriageYear: Int,
        endYear: Int? = nil
    ) throws -> URL {
        try makeFamilyBirthSearchUrl(
            fatherName: normalizeForHiskiQuery(fatherName),
            fatherPatronymic: hiskiPatronymicSearchInput(for: fatherPatronymic),
            motherName: normalizeForHiskiQuery(motherName),
            motherPatronymic: hiskiPatronymicSearchInput(for: motherPatronymic),
            startYear: marriageYear - Self.yearsBeforeMarriage,
            endYear: endYear ?? marriageYear + Self.childbearingWindowYears
        )
    }

    func buildFamilyBirthSearchUrl(
        fatherName: String,
        fatherPatronymic: String?,
        motherName: String,
        motherPatronymic: String?,
        startYear: Int,
        endYear: Int? = nil
    ) throws -> URL {
        try makeFamilyBirthSearchUrl(
            fatherName: normalizeForHiskiQuery(fatherName),
            fatherPatronymic: hiskiPatronymicSearchInput(for: fatherPatronymic),
            motherName: normalizeForHiskiQuery(motherName),
            motherPatronymic: hiskiPatronymicSearchInput(for: motherPatronymic),
            startYear: startYear,
            endYear: endYear ?? startYear + Self.childbearingWindowYears
        )
    }

    func buildFamilyBirthSearchRequests(
        fatherName: String,
        fatherPatronymic: String?,
        motherName: String,
        motherPatronymic: String?,
        marriageYear: Int,
        endYear: Int? = nil
    ) throws -> [FamilyBirthSearchRequest] {
        try buildFamilyBirthSearchRequests(
            fatherName: fatherName,
            fatherPatronymic: fatherPatronymic,
            motherName: motherName,
            motherPatronymic: motherPatronymic,
            startYear: marriageYear - Self.yearsBeforeMarriage,
            endYear: endYear ?? marriageYear + Self.childbearingWindowYears
        )
    }

    func buildFamilyBirthSearchRequests(
        fatherName: String,
        fatherPatronymic: String?,
        motherName: String,
        motherPatronymic: String?,
        startYear: Int,
        endYear: Int? = nil
    ) throws -> [FamilyBirthSearchRequest] {
        var requests: [FamilyBirthSearchRequest] = []
        var seenURLs: Set<String> = []
        let boundedEndYear = max(startYear, endYear ?? startYear + Self.childbearingWindowYears)

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
                startYear: startYear,
                endYear: boundedEndYear
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

    static func familyBirthEndYear(
        marriageYear: Int,
        husbandDeathDate: String?,
        wifeDeathDate: String?
    ) -> Int {
        let defaultEndYear = marriageYear + childbearingWindowYears
        let earliestSpouseDeathYear = [
            extractYear(from: husbandDeathDate),
            extractYear(from: wifeDeathDate)
        ]
            .compactMap { $0 }
            .min()

        return max(marriageYear, min(earliestSpouseDeathYear ?? defaultEndYear, defaultEndYear))
    }

    static func familyBirthEndYear(
        startYear: Int,
        husbandDeathDate: String?,
        wifeDeathDate: String?
    ) -> Int {
        let defaultEndYear = startYear + childbearingWindowYears
        let earliestSpouseDeathYear = [
            extractYear(from: husbandDeathDate),
            extractYear(from: wifeDeathDate)
        ]
            .compactMap { $0 }
            .min()

        return max(startYear, min(earliestSpouseDeathYear ?? defaultEndYear, defaultEndYear))
    }

    private func makeFamilyBirthSearchUrl(
        fatherName: String,
        fatherPatronymic: String?,
        motherName: String,
        motherPatronymic: String?,
        startYear: Int,
        endYear: Int?
    ) throws -> URL {
        let boundedEndYear = max(startYear, endYear ?? startYear + Self.childbearingWindowYears)

        let params = [
            "komento": "haku",
            "srk": parishes,
            "kirja": "kastetut",
            "kieli": "en",
            "etunimi": "",
            "alkuvuosi": String(startYear),
            "loppuvuosi": String(boundedEndYear),
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

    private static func extractYear(from rawDate: String?) -> Int? {
        guard let rawDate,
              let yearRange = rawDate.range(of: #"\b\d{3,4}\b"#, options: .regularExpression) else {
            return nil
        }

        return Int(rawDate[yearRange])
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
        case "pietarint":
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
