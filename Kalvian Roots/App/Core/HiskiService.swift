//
//  HiskiService.swift
//  Kalvian Roots
//
//  Queries hiski.genealogia.fi using algorithm from hiski.py
//  Automatically finds matching records and returns citation URLs
//
//  Created by Michael Bendio on 10/1/25.
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
}

// MARK: - WebView Window Manager

#if os(macOS)
@MainActor
class HiskiWebViewManager: NSObject, WKNavigationDelegate {
    static let shared = HiskiWebViewManager()
    
    private var recordWindow: NSWindow?
    
    private let recordWindowX: CGFloat = 1300
    private let recordWindowY: CGFloat = 250
    private let recordWindowWidth: CGFloat = 1200
    private let recordWindowHeight: CGFloat = 450
    
    private override init() {
        super.init()
    }
    
    func openRecordView(url: URL) {
        // If window exists, reuse it
        if let existingWebView = recordWindow?.contentView as? WKWebView {
            existingWebView.load(URLRequest(url: url))
            recordWindow?.makeKeyAndOrderFront(nil)
            logInfo(.app, "🪟 Reused Hiski record window")
            return
        }
        
        // Create new window
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
    
    func closeRecordWindow() {
        recordWindow?.orderOut(nil)
        logInfo(.app, "🪟 Hidden Hiski record window")
    }
    
    func closeAllWindows() {
        closeRecordWindow()
    }
    
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            logDebug(.app, "WebView finished loading")
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
    
    func openRecordView(url: URL) {
        // On iOS, just open in Safari
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                logInfo(.app, "📱 Opened Hiski record in Safari")
            } else {
                logError(.app, "Failed to open record URL in Safari")
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
    private let nameEquivalenceManager: NameEquivalenceManager
    private let parishes = "0053,0093,0165,0183,0218,0172,0265,0295,0301,0386,0555,0581,0614"
    private var currentFamilyId: String?
    
    init(nameEquivalenceManager: NameEquivalenceManager) {
        self.nameEquivalenceManager = nameEquivalenceManager
    }
    
    func setCurrentFamily(_ familyId: String) {
        self.currentFamilyId = familyId
    }
    
    // MARK: - Query Methods (matching hiski.py algorithm)
    
    func queryDeath(name: String, date: String) async throws -> HiskiCitation {
        let swedishName = getSwedishEquivalent(for: name)
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
        
        // Find matching record URL from HTML (matching hiski.py algorithm)
        guard let recordUrl = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
            logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "✅ Found matching record: \(recordUrl)")
        
        // Fetch the record page
        guard let url = URL(string: "https://hiski.genealogia.fi" + recordUrl) else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        let (recordData, _) = try await URLSession.shared.data(from: url)
        guard let recordHtml = String(data: recordData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Extract citation URL from record page
        guard let citationUrl = extractCitationUrl(from: recordHtml) else {
            logWarn(.app, "⚠️ No citation URL found in record page")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "📋 Citation URL: \(citationUrl)")
        
        // Open record window
        await openRecordWindow(URL(string: citationUrl)!)
        
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
        let swedishName = getSwedishEquivalent(for: name)
        let firstName = swedishName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? swedishName
        
        var fatherFirstName: String? = nil
        if let father = fatherName {
            let swedishFather = getSwedishEquivalent(for: father)
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
        guard let recordUrl = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
            logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "✅ Found matching record: \(recordUrl)")
        
        // Fetch the record page
        guard let url = URL(string: "https://hiski.genealogia.fi" + recordUrl) else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        let (recordData, _) = try await URLSession.shared.data(from: url)
        guard let recordHtml = String(data: recordData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Extract citation URL
        guard let citationUrl = extractCitationUrl(from: recordHtml) else {
            logWarn(.app, "⚠️ No citation URL found in record page")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "📋 Citation URL: \(citationUrl)")
        
        // Open record window
        await openRecordWindow(URL(string: citationUrl)!)
        
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
        let swedishHusband = getSwedishEquivalent(for: husbandName)
        let swedishWife = getSwedishEquivalent(for: wifeName)
        
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
        guard let recordUrl = findMatchingRecordUrl(from: searchHtml, queryDate: formattedDate) else {
            logWarn(.app, "⚠️ No matching record found for date: \(formattedDate)")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "✅ Found matching record: \(recordUrl)")
        
        // Fetch record page
        guard let url = URL(string: "https://hiski.genealogia.fi" + recordUrl) else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        let (recordData, _) = try await URLSession.shared.data(from: url)
        guard let recordHtml = String(data: recordData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        // Extract citation
        guard let citationUrl = extractCitationUrl(from: recordHtml) else {
            logWarn(.app, "⚠️ No citation URL found in record page")
            throw HiskiServiceError.noRecordFound
        }
        
        logInfo(.app, "📋 Citation URL: \(citationUrl)")
        
        // Open record window
        await openRecordWindow(URL(string: citationUrl)!)
        
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
        // Step 1: Extract the first date from <LI>Years line
        // Pattern: <LI>Years dd.mm.yyyy - dd.mm.yyyy
        let yearsPattern = "<LI>\\s*Years\\s+([0-9.]+)\\s*-\\s*([0-9.]+)"
        
        guard let yearsRegex = try? NSRegularExpression(pattern: yearsPattern, options: [.caseInsensitive]),
              let yearsMatch = yearsRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let firstDateRange = Range(yearsMatch.range(at: 1), in: html) else {
            logWarn(.app, "⚠️ Could not find <LI>Years line in search results")
            return nil
        }
        
        let firstDate = String(html[firstDateRange])
        logInfo(.app, "📅 Looking for record with date: \(firstDate)")
        
        // Step 2: Find all sl.gif links with their adjacent dates
        // Pattern: <a href="..."><img src="/historia/sl.gif"...></a> followed by date
        let linkPattern = "<a\\s+href=\"([^\"]+)\">\\s*<img[^>]+src=\"/historia/sl\\.gif\"[^>]*>\\s*</a>\\s*([0-9.]+)"
        
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive]) else {
            return nil
        }
        
        let matches = linkRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        // Step 3: Find the link whose date matches firstDate
        for match in matches {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let dateRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            
            let href = String(html[hrefRange])
            let dateText = String(html[dateRange]).trimmingCharacters(in: .whitespaces)
            
            logDebug(.app, "  Checking: \(href) with date \(dateText)")
            
            if dateText == firstDate {
                logInfo(.app, "✅ Found matching link: \(href)")
                return href
            }
        }
        
        logWarn(.app, "⚠️ No sl.gif link found matching date \(firstDate)")
        return nil
    }
    
    private func extractCitationUrl(from html: String) -> String? {
        // Extract "Link to this event" URL: /hiski?en+t1234567
        // Pattern: HREF="(/hiski?en+t\d+)"
        let pattern = "HREF=\"(/hiski\\?en\\+t\\d+)\""
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let urlRange = Range(match.range(at: 1), in: html) else {
            logWarn(.app, "⚠️ Could not find citation URL in record page")
            return nil
        }
        
        let citationPath = String(html[urlRange])
        return "https://hiski.genealogia.fi" + citationPath
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
        components.path = "/hiski"
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = components.url else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        return url
    }
    
    // MARK: - Window Management
    
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
