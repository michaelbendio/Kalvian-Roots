//
//  HiskiService.swift
//  Kalvian Roots
//
//  Queries hiski.genealogia.fi, opens results in browser, extracts citation URLs
//
//  Created by Michael Bendio on 10/1/25.
//

import Foundation
import SwiftUI
import Combine
#if os(macOS)
import AppKit
import WebKit
#elseif os(iOS)
import SafariServices
#endif

// MARK: - Error Types

enum HiskiServiceError: Error {
    case sessionFailed
    case invalidDate
    case urlCreationFailed
    case browserOpenFailed
    case noRecordFound
}

// MARK: - WebView Window Manager

#if os(macOS)
@MainActor
class HiskiWebViewManager: NSObject, WKNavigationDelegate {
    static let shared = HiskiWebViewManager()
    
    private var searchWindow: NSWindow?
    private var recordWindow: NSWindow?
    private var urlObservers = Set<AnyCancellable>()
    
    private let searchWindowX: CGFloat = 1300
    private let searchWindowY: CGFloat = 800
    private let searchWindowWidth: CGFloat = 600
    private let searchWindowHeight: CGFloat = 800
    private let addressBarHeight: CGFloat = 24
    private let addressBarPadding: CGFloat = 10
    
    private let recordWindowX: CGFloat = 1300
    private let recordWindowY: CGFloat = 250
    private let recordWindowWidth: CGFloat = 1200  // Doubled from 600
    private let recordWindowHeight: CGFloat = 450
    
    private override init() {
        super.init()
    }
    
    func openSearchResults(url: URL) {
        closeSearchWindow()
        
        let addressBarWidth = searchWindowWidth - (addressBarPadding * 2)
        let webViewHeight = searchWindowHeight - addressBarHeight - addressBarPadding
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: searchWindowWidth, height: searchWindowHeight))
        
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: searchWindowWidth, height: webViewHeight))
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        
        let addressBarY = searchWindowHeight - addressBarHeight - (addressBarPadding / 2)
        let addressField = NSTextField(frame: NSRect(x: addressBarPadding,
                                                     y: addressBarY,
                                                     width: addressBarWidth,
                                                     height: addressBarHeight))
        addressField.isEditable = false
        addressField.isSelectable = true
        addressField.isBordered = true
        addressField.backgroundColor = .controlBackgroundColor
        addressField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        addressField.stringValue = url.absoluteString
        addressField.lineBreakMode = .byTruncatingMiddle
        
        containerView.addSubview(addressField)
        containerView.addSubview(webView)
        
        webView.publisher(for: \.url)
            .sink { [weak addressField] newUrl in
                addressField?.stringValue = newUrl?.absoluteString ?? ""
            }
            .store(in: &urlObservers)
        
        searchWindow = NSWindow(
            contentRect: NSRect(x: searchWindowX, y: searchWindowY, width: searchWindowWidth, height: searchWindowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        searchWindow?.title = "Hiski Search Results"
        searchWindow?.contentView = containerView
        searchWindow?.makeKeyAndOrderFront(nil)
        searchWindow?.level = .floating
        
        webView.load(URLRequest(url: url))
        
        logInfo(.app, "🪟 Opened Hiski search window")
    }
    
    func openRecordView(url: URL) {
        closeRecordWindow()
        
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: recordWindowWidth, height: recordWindowHeight))
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        
        recordWindow = NSWindow(
            contentRect: NSRect(x: recordWindowX, y: recordWindowY, width: recordWindowWidth, height: recordWindowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        recordWindow?.title = "Hiski Record"
        recordWindow?.contentView = webView
        recordWindow?.makeKeyAndOrderFront(nil)
        recordWindow?.level = .floating
        
        webView.load(URLRequest(url: url))
        
        logInfo(.app, "🪟 Opened Hiski record window")
    }
    
    func closeSearchWindow() {
        searchWindow?.close()
        searchWindow = nil
        urlObservers.removeAll()
    }
    
    func closeRecordWindow() {
        recordWindow?.close()
        recordWindow = nil
    }
    
    func closeAllWindows() {
        closeSearchWindow()
        closeRecordWindow()
    }
    
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            logDebug(.app, "WebView finished loading")
        }
    }
}
#elseif os(iOS)
@MainActor
class HiskiWebViewManager {
    static let shared = HiskiWebViewManager()
    private var presentingViewController: UIViewController?
    
    private init() {}
    
    func setPresentingViewController(_ viewController: UIViewController) {
        self.presentingViewController = viewController
    }
    
    func openSearchResults(url: URL) {
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                logInfo(.app, "📱 Opened Hiski search in Safari")
            } else {
                logError(.app, "Failed to open search URL in Safari")
            }
        }
    }
    
    func openRecordView(url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    logInfo(.app, "📱 Opened Hiski record in Safari (new tab)")
                } else {
                    logError(.app, "Failed to open record URL in Safari")
                }
            }
        }
    }
    
    func closeAllWindows() {
        // Safari manages its own tabs
    }
}
#endif

// MARK: - HiskiService

class HiskiService {
    private let baseUrl = "https://hiski.genealogia.fi/hiski/"
    // NOTE: The srk parameter needs the "srk=" prefix as shown in working Python code
    private let parishes = "srk=0053%2C0093%2C0165%2C0183%2C0218%2C0172%2C0265%2C0295%2C0301%2C0386%2C0555%2C0581%2C0614"
    
    private var currentFamilyId: String = ""
    private let nameEquivalenceManager: NameEquivalenceManager
    
    // MARK: - Initialization
    
    init(nameEquivalenceManager: NameEquivalenceManager = NameEquivalenceManager()) {
        self.nameEquivalenceManager = nameEquivalenceManager
        
        // TEMPORARY FIX: Ensure critical name equivalences exist for Hiski queries
        // (This works around potential UserDefaults persistence issues)
        let criticalEquivalences = [
            ("Pietari", "Petrus"),
            ("Juho", "Johan"),
            ("Matti", "Matias"),
            ("Antti", "Anders"),
            ("Erkki", "Erik"),
            ("Heikki", "Henrik"),
            ("Liisa", "Elisabet"),
            ("Brita", "Birgitta")
        ]
        
        for (name1, name2) in criticalEquivalences {
            if !nameEquivalenceManager.areNamesEquivalent(name1, name2) {
                logInfo(.app, "➕ Adding missing equivalence: \(name1) ↔ \(name2)")
                nameEquivalenceManager
                    .addEquivalence(between: name1, and: name2)
            }
        }
    }
 
    // MARK: - Public Methods
    
    func setCurrentFamily(_ familyId: String) {
        self.currentFamilyId = familyId
    }
    
    // MARK: - Query Methods (FIXED - No Session Required)
    
    func queryBirth(name: String, date: String, fatherName: String? = nil) async throws -> HiskiCitation {
        // Translate Finnish name to Swedish equivalent
        let swedishName = getSwedishEquivalent(for: name)
        let firstName = swedishName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishName
        
        // Extract father's first name if provided
        var fatherFirstName: String? = nil
        if let father = fatherName {
            let swedishFather = getSwedishEquivalent(for: father)
            fatherFirstName = swedishFather.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let formattedDate = formatDateForHiski(date)
        
        // Build search URL (no session needed)
        let searchUrl = try buildBirthSearchUrl(name: firstName, date: formattedDate, fatherName: fatherFirstName)
        
        // Fetch search results to extract record ID
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Open search window for validation
        await openSearchWindow(searchUrl)
        
        // Extract record link from search results
        if let recordLink = extractRecordLink(from: searchHtml) {
            // Extract record ID from the link
            // Link format: /hiski?en+0265+kastetut+4085100
            if let recordId = extractRecordIdFromLink(recordLink) {
                // Build final citation URL
                let citationUrl = "https://hiski.genealogia.fi/hiski?en+t\(recordId)"
                
                // Open record window for validation
                guard let recordUrl = URL(string: citationUrl) else {
                    logError(.app, "Failed to create record URL: \(citationUrl)")
                    throw HiskiServiceError.urlCreationFailed
                }
                await openRecordWindow(recordUrl)
                
                return HiskiCitation(
                    recordType: .birth,
                    personName: name,
                    date: date,
                    url: citationUrl,
                    recordId: recordId,
                    spouse: nil
                )
            }
        }
        
        // Fallback: return search URL if we couldn't extract record
        throw HiskiServiceError.noRecordFound
    }
    
    func queryDeath(name: String, date: String) async throws -> HiskiCitation {
        // Translate Finnish name to Swedish equivalent
        let swedishName = getSwedishEquivalent(for: name)
        let firstName = swedishName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishName
        
        let formattedDate = formatDateForHiski(date)
        
        logInfo(.app, "🔍 Hiski Death Query:")
        logInfo(.app, "  Original name: \(name)")
        logInfo(.app, "  Swedish name: \(swedishName)")
        logInfo(.app, "  First name: \(firstName)")
        logInfo(.app, "  Original date: \(date)")
        logInfo(.app, "  Formatted date: \(formattedDate)")
        
        // Build search URL (no session needed)
        let searchUrl = try buildDeathSearchUrl(name: firstName, date: formattedDate)
        
        logInfo(.app, "📍 Search URL: \(searchUrl.absoluteString)")
        
        // Fetch search results to extract record ID
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Open search window for validation
        await openSearchWindow(searchUrl)
        
        // Extract record link from search results
        if let recordLink = extractRecordLink(from: searchHtml) {
            // Extract record ID from the link
            if let recordId = extractRecordIdFromLink(recordLink) {
                // Build final citation URL
                let citationUrl = "https://hiski.genealogia.fi/hiski?en+t\(recordId)"
                
                // Open record window for validation
                guard let recordUrl = URL(string: citationUrl) else {
                    logError(.app, "Failed to create record URL: \(citationUrl)")
                    throw HiskiServiceError.urlCreationFailed
                }
                await openRecordWindow(recordUrl)
                
                return HiskiCitation(
                    recordType: .death,
                    personName: name,
                    date: date,
                    url: citationUrl,
                    recordId: recordId,
                    spouse: nil
                )
            }
        }
        
        // Fallback: return search URL if we couldn't extract record
        throw HiskiServiceError.noRecordFound
    }
    
    func queryMarriage(husbandName: String, wifeName: String, date: String) async throws -> HiskiCitation {
        // Translate names to Swedish equivalents
        let swedishHusband = getSwedishEquivalent(for: husbandName)
        let swedishWife = getSwedishEquivalent(for: wifeName)
        
        let husbandFirst = swedishHusband.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishHusband
        let wifeFirst = swedishWife.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishWife
        
        let formattedDate = formatDateForHiski(date)
        
        // Build search URL (no session needed)
        let searchUrl = try buildMarriageSearchUrl(husbandName: husbandFirst, wifeName: wifeFirst, date: formattedDate)
        
        // Fetch search results to extract record ID
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Open search window for validation
        await openSearchWindow(searchUrl)
        
        // Extract record link from search results
        if let recordLink = extractRecordLink(from: searchHtml) {
            // Extract record ID from the link
            if let recordId = extractRecordIdFromLink(recordLink) {
                // Build final citation URL
                let citationUrl = "https://hiski.genealogia.fi/hiski?en+t\(recordId)"
                
                // Open record window for validation
                guard let recordUrl = URL(string: citationUrl) else {
                    logError(.app, "Failed to create record URL: \(citationUrl)")
                    throw HiskiServiceError.urlCreationFailed
                }
                await openRecordWindow(recordUrl)
                
                return HiskiCitation(
                    recordType: .marriage,
                    personName: husbandName,
                    date: date,
                    url: citationUrl,
                    recordId: recordId,
                    spouse: wifeName
                )
            }
        }
        
        // Fallback: return search URL if we couldn't extract record
        throw HiskiServiceError.noRecordFound
    }
    
    // MARK: - URL Building (No Session Required)
    
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
            "maxkpl": "15",
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
    
    private func buildDeathSearchUrl(name: String, date: String) throws -> URL {
        let params = [
            "komento": "haku",
            "srk": parishes,
            "kirja": "haudatut",
            "kieli": "en",
            "alkuvuosi": date,
            "loppuvuosi": date,
            "maxkpl": "15",
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
            "maxkpl": "15",
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
        components.path = "/hiski"  // Changed from "/hiski/"
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = components.url else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        return url
    }
    
    // MARK: - HTML Parsing
    
    private func extractRecordLink(from html: String) -> String? {
        // Pattern: <a href="/hiski?en+0265+haudatut+6028"><img src="/historia/sl.gif" border=0 alt="*"></a>
        // Be flexible about whitespace and attributes
        let pattern = "<a\\s+href=\"(/hiski\\?en\\+[^\"]+)\"[^>]*><img\\s+src=\"/historia/sl\\.gif\""
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let linkRange = Range(match.range(at: 1), in: html) else {
            logWarn(.app, "⚠️ Could not find record link in search results")
            logDebug(.app, "📄 HTML snippet (first 1000 chars):")
            logDebug(.app, String(html.prefix(1000)))
            
            // Try to find ANY link with /hiski?en+ pattern for debugging
            if let debugRegex = try? NSRegularExpression(pattern: "/hiski\\?en\\+[^\"\\s]+", options: []),
               let debugMatch = debugRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let debugRange = Range(debugMatch.range, in: html) {
                logDebug(.app, "🔍 Found hiski link in HTML: \(String(html[debugRange]))")
            }
            
            return nil
        }
        
        let link = String(html[linkRange])
        logInfo(.app, "✅ Found record link: \(link)")
        return link
    }
    
    private func extractRecordIdFromLink(_ link: String) -> String? {
        // Link format: /hiski?en+0265+haudatut+6028
        // We want the last number (6028)
        let components = link.components(separatedBy: "+")
        guard let recordId = components.last else {
            logWarn(.app, "⚠️ Could not extract record ID from link: \(link)")
            return nil
        }
        
        logInfo(.app, "✅ Extracted record ID: \(recordId)")
        return recordId
    }
    
    // MARK: - Browser Window Management
    
    @MainActor
    private func openSearchWindow(_ url: URL) async {
        HiskiWebViewManager.shared.openSearchResults(url: url)
    }
    
    @MainActor
    private func openRecordWindow(_ url: URL) async {
        HiskiWebViewManager.shared.openRecordView(url: url)
    }
    
    // MARK: - Name Translation
    
    private func getSwedishEquivalent(for finnishName: String) -> String {
        // Get all equivalent names
        let equivalents = nameEquivalenceManager.getEquivalentNames(for: finnishName)
        
        logDebug(.app, "🔍 Swedish equivalent lookup for '\(finnishName)':")
        logDebug(.app, "   Found equivalents: \(Array(equivalents).sorted())")
        
        // For Hiski queries in Swedish records, prefer Swedish/Latin forms
        let swedishPreferred = ["Petrus", "Pehr", "Johannes", "Henricus", "Henrik", "Ericus", "Erik",
                                "Matthias", "Matts", "Mats", "Elisabet", "Birgitta", "Brita"]
        
        // Check if any equivalent matches our preferred Swedish forms
        for preferred in swedishPreferred {
            if equivalents.contains(where: { $0.lowercased() == preferred.lowercased() }) {
                logInfo(.app, "✅ Translated '\(finnishName)' → '\(preferred)' for Hiski query")
                return preferred
            }
        }
        
        // If no Swedish equivalent found, return original name
        logWarn(.app, "⚠️ No Swedish equivalent found for '\(finnishName)', using original")
        return finnishName
    }
    
    // MARK: - Date Formatting
    
    private func formatDateForHiski(_ dateString: String) -> String {
        var cleaned = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove any leading zeros from day/month
        if cleaned.contains(".") {
            let components = cleaned.components(separatedBy: ".")
            if components.count == 3 {
                let day = String(Int(components[0]) ?? 0)
                let month = String(Int(components[1]) ?? 0)
                let year = components[2]
                return "\(day).\(month).\(year)"
            }
        }
        
        // Otherwise return as-is (already just a year)
        return cleaned
    }
}
