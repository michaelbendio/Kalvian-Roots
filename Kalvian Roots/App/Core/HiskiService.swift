//
//  HiskiService.swift
//  Kalvian Roots
//
//  Queries hiski.genealogia.fi, opens results in browser, adds citation to clipboard
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
}

// MARK: - WebView Window Manager

#if os(macOS)
@MainActor
class HiskiWebViewManager: NSObject, WKNavigationDelegate {
    static let shared = HiskiWebViewManager()
    
    private var searchWindow: NSWindow?
    private var recordWindow: NSWindow?
    private var urlObservers = Set<AnyCancellable>()
    
    private override init() {
        super.init()
    }
    
    func openSearchResults(url: URL) {
        closeSearchWindow()
        
        // Create WKWebView with visible navigation
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        
        // Create container view with address bar
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        
        // Address bar
        let addressField = NSTextField(frame: NSRect(x: 10, y: 770, width: 1180, height: 24))
        addressField.isEditable = false
        addressField.isBordered = true
        addressField.backgroundColor = .controlBackgroundColor
        addressField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        addressField.stringValue = url.absoluteString
        addressField.lineBreakMode = .byTruncatingMiddle
        
        // WebView (below address bar)
        webView.frame = NSRect(x: 0, y: 0, width: 1200, height: 765)
        
        containerView.addSubview(addressField)
        containerView.addSubview(webView)
        
        // Update address field when URL changes
        webView.publisher(for: \.url)
            .sink { [weak addressField] newUrl in
                addressField?.stringValue = newUrl?.absoluteString ?? ""
            }
            .store(in: &urlObservers)
        
        // Create window
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered,
                             defer: false)
        window.title = "Hiski Search Results"
        window.contentView = containerView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        
        searchWindow = window
        webView.load(URLRequest(url: url))
    }
    
    func openRecordView(url: URL) {
        closeRecordWindow()
        
        // Create WKWebView with visible navigation
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        
        // Create container view with address bar
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        
        // Address bar
        let addressField = NSTextField(frame: NSRect(x: 10, y: 770, width: 980, height: 24))
        addressField.isEditable = false
        addressField.isBordered = true
        addressField.backgroundColor = .controlBackgroundColor
        addressField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        addressField.stringValue = url.absoluteString
        addressField.lineBreakMode = .byTruncatingMiddle
        
        // WebView (below address bar)
        webView.frame = NSRect(x: 0, y: 0, width: 1000, height: 765)
        
        containerView.addSubview(addressField)
        containerView.addSubview(webView)
        
        // Update address field when URL changes
        webView.publisher(for: \.url)
            .sink { [weak addressField] newUrl in
                addressField?.stringValue = newUrl?.absoluteString ?? ""
            }
            .store(in: &urlObservers)
        
        // Create window
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 1000, height: 800),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered,
                             defer: false)
        window.title = "Hiski Record"
        window.contentView = containerView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        
        recordWindow = window
        webView.load(URLRequest(url: url))
    }
    
    func closeAllWindows() {
        closeSearchWindow()
        closeRecordWindow()
    }
    
    private func closeSearchWindow() {
        if let window = searchWindow {
            window.orderOut(nil)
            window.close()
            searchWindow = nil
        }
    }
    
    private func closeRecordWindow() {
        if let window = recordWindow {
            window.orderOut(nil)
            window.close()
            recordWindow = nil
        }
    }
}
#elseif os(iOS)
@MainActor
class HiskiWebViewManager: NSObject {
    static let shared = HiskiWebViewManager()
    
    private var searchSafari: SFSafariViewController?
    private var recordSafari: SFSafariViewController?
    private weak var presentingViewController: UIViewController?
    
    private override init() {
        super.init()
    }
    
    func setPresentingViewController(_ viewController: UIViewController) {
        self.presentingViewController = viewController
    }
    
    func openSearchResults(url: URL) {
        guard let presenter = presentingViewController else {
            logError(.app, "No presenting view controller for Safari")
            return
        }
        
        // Dismiss existing search if present
        if let existing = searchSafari {
            existing.dismiss(animated: false)
        }
        
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = .systemBlue
        safari.dismissButtonStyle = .close
        
        searchSafari = safari
        presenter.present(safari, animated: true)
    }
    
    func openRecordView(url: URL) {
        guard let presenter = presentingViewController else {
            logError(.app, "No presenting view controller for Safari")
            return
        }
        
        // Dismiss existing record if present
        if let existing = recordSafari {
            existing.dismiss(animated: false)
        }
        
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = .systemGreen
        safari.dismissButtonStyle = .close
        
        recordSafari = safari
        presenter.present(safari, animated: true)
    }
    
    func closeAllWindows() {
        searchSafari?.dismiss(animated: true)
        recordSafari?.dismiss(animated: true)
        searchSafari = nil
        recordSafari = nil
    }
}
#endif

// MARK: - HiskiService

class HiskiService {
    private let baseUrl = "https://hiski.genealogia.fi/hiski/"
    private let parishes = "srk=0053%2C0093%2C0165%2C0183%2C0218%2C0172%2C0265%2C0295%2C0301%2C0386%2C0555%2C0581%2C0614"
    
    private var currentFamilyId: String = ""
    
    // MARK: - Public Methods
    
    func setCurrentFamily(_ familyId: String) {
        self.currentFamilyId = familyId
    }
    
    func queryBirth(name: String, date: String, fatherName: String? = nil) async throws -> HiskiCitation {
        let session = try await getSession()
        let firstName = name.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        
        // Extract father's first name if provided
        var fatherFirstName: String? = nil
        if let father = fatherName {
            fatherFirstName = father.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let searchUrl = try buildBirthSearchUrl(session: session, name: firstName, date: date, fatherName: fatherFirstName)
        
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        await openSearchWindow(searchUrl)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        if let recordLink = extractRecordLink(from: searchHtml, session: session) {
            let recordUrl = URL(string: "https://hiski.genealogia.fi\(recordLink)")!
            let (recordData, _) = try await URLSession.shared.data(from: recordUrl)
            guard let recordHtml = String(data: recordData, encoding: .isoLatin1) else {
                throw HiskiServiceError.sessionFailed
            }
            
            if let recordId = extractRecordId(from: recordHtml) {
                let citationUrl = "https://hiski.genealogia.fi/hiski?en+t\(recordId)"
                await openRecordWindow(URL(string: citationUrl)!)
                
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
        
        return HiskiCitation(
            recordType: .birth,
            personName: name,
            date: date,
            url: searchUrl.absoluteString,
            recordId: session,
            spouse: nil
        )
    }
    
    func queryDeath(name: String, date: String) async throws -> HiskiCitation {
        let session = try await getSession()
        let firstName = name.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        let searchUrl = try buildDeathSearchUrl(session: session, name: firstName, date: date)
        
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        await openSearchWindow(searchUrl)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        if let recordLink = extractRecordLink(from: searchHtml, session: session) {
            let recordUrl = URL(string: "https://hiski.genealogia.fi\(recordLink)")!
            let (recordData, _) = try await URLSession.shared.data(from: recordUrl)
            guard let recordHtml = String(data: recordData, encoding: .isoLatin1) else {
                throw HiskiServiceError.sessionFailed
            }
            
            if let recordId = extractRecordId(from: recordHtml) {
                let citationUrl = "https://hiski.genealogia.fi/hiski?en+t\(recordId)"
                await openRecordWindow(URL(string: citationUrl)!)
                
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
        
        return HiskiCitation(
            recordType: .death,
            personName: name,
            date: date,
            url: searchUrl.absoluteString,
            recordId: session,
            spouse: nil
        )
    }
    
    func queryMarriage(husbandName: String, wifeName: String, date: String) async throws -> HiskiCitation {
        let session = try await getSession()
        let husbandFirst = husbandName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? husbandName
        let wifeFirst = wifeName.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? wifeName
        let searchUrl = try buildMarriageSearchUrl(session: session, husbandName: husbandFirst, wifeName: wifeFirst, date: date)
        
        let (searchData, _) = try await URLSession.shared.data(from: searchUrl)
        guard let searchHtml = String(data: searchData, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        await openSearchWindow(searchUrl)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        if let recordLink = extractRecordLink(from: searchHtml, session: session) {
            let recordUrl = URL(string: "https://hiski.genealogia.fi\(recordLink)")!
            let (recordData, _) = try await URLSession.shared.data(from: recordUrl)
            guard let recordHtml = String(data: recordData, encoding: .isoLatin1) else {
                throw HiskiServiceError.sessionFailed
            }
            
            if let recordId = extractRecordId(from: recordHtml) {
                let citationUrl = "https://hiski.genealogia.fi/hiski?en+t\(recordId)"
                await openRecordWindow(URL(string: citationUrl)!)
                
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
        
        return HiskiCitation(
            recordType: .marriage,
            personName: husbandName,
            date: date,
            url: searchUrl.absoluteString,
            recordId: session,
            spouse: wifeName
        )
    }
    
    func closeWebViewWindows() {
        Task { @MainActor in
            HiskiWebViewManager.shared.closeAllWindows()
        }
    }
    
    // MARK: - Private Helper Methods
    
    @MainActor
    private func openSearchWindow(_ url: URL) async {
        HiskiWebViewManager.shared.openSearchResults(url: url)
    }
    
    @MainActor
    private func openRecordWindow(_ url: URL) async {
        HiskiWebViewManager.shared.openRecordView(url: url)
    }
    
    private func getSession() async throws -> String {
        guard let url = URL(string: baseUrl) else {
            throw HiskiServiceError.sessionFailed
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .isoLatin1) else {
            throw HiskiServiceError.sessionFailed
        }
        
        let pattern = "hiski/([A-Za-z0-9]{5})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let sessionRange = Range(match.range(at: 1), in: html) else {
            throw HiskiServiceError.sessionFailed
        }
        
        return String(html[sessionRange])
    }
    
    private func buildBirthSearchUrl(session: String, name: String, date: String, fatherName: String? = nil) throws -> URL {
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
        
        // Add father's first name if available (narrows search results significantly)
        if let fatherFirst = fatherName, !fatherFirst.isEmpty {
            params["ietunimi"] = fatherFirst
        }
        
        return try buildSearchUrl(session: session, params: params)
    }
    
    private func buildDeathSearchUrl(session: String, name: String, date: String) throws -> URL {
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
        
        return try buildSearchUrl(session: session, params: params)
    }
    
    private func buildMarriageSearchUrl(session: String, husbandName: String, wifeName: String, date: String) throws -> URL {
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
        
        return try buildSearchUrl(session: session, params: params)
    }
    
    private func buildSearchUrl(session: String, params: [String: String]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hiski.genealogia.fi"
        components.path = "/hiski/\(session)"
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = components.url else {
            throw HiskiServiceError.urlCreationFailed
        }
        
        return url
    }
    
    private func extractRecordLink(from html: String, session: String) -> String? {
        let pattern = "<a href=\"([^\"]+)\">\\s*<img src=\"/historia/sl\\.gif\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let linkRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        
        return String(html[linkRange])
    }
    
    private func extractRecordId(from html: String) -> String? {
        let pattern = "\\[\\s*(\\d+)\\s*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let idRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        
        return String(html[idRange])
    }
}
