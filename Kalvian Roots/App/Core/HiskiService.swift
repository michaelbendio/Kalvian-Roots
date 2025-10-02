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
}

// MARK: - WebView Window Manager

#if os(macOS)
@MainActor
class HiskiWebViewManager: NSObject, WKNavigationDelegate {
    static let shared = HiskiWebViewManager()
    
    private var searchWindow: NSWindow?
    private var recordWindow: NSWindow?
    
    private override init() {
        super.init()
    }
    
    func openSearchResults(url: URL) {
        closeSearchWindow()
        
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        webView.navigationDelegate = self
        
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered,
                             defer: false)
        window.title = "Hiski Search Results"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        
        searchWindow = window
        webView.load(URLRequest(url: url))
    }
    
    func openRecordView(url: URL) {
        closeRecordWindow()
        
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        webView.navigationDelegate = self
        
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 1000, height: 800),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered,
                             defer: false)
        window.title = "Hiski Record"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        
        recordWindow = window
        webView.load(URLRequest(url: url))
    }
    
    func closeAllWindows() {
        print("DEBUG: closeAllWindows called")
        closeSearchWindow()
        closeRecordWindow()
    }
    
    private func closeSearchWindow() {
        print("DEBUG: closeSearchWindow - window exists: \(searchWindow != nil)")
        if let window = searchWindow {
            window.orderOut(nil)
            window.close()
            searchWindow = nil
            print("DEBUG: Search window closed")
        }
    }
    
    private func closeRecordWindow() {
        print("DEBUG: closeRecordWindow - window exists: \(recordWindow != nil)")
        if let window = recordWindow {
            window.orderOut(nil)
            window.close()
            recordWindow = nil
            print("DEBUG: Record window closed")
        }
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
    
    func queryBirth(name: String, date: String) async throws -> HiskiCitation {
        let session = try await getSession()
        let firstName = name.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        let searchUrl = try buildBirthSearchUrl(session: session, name: firstName, date: date)
        
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
            #if os(macOS)
            HiskiWebViewManager.shared.closeAllWindows()
            #endif
        }
    }
    
    // MARK: - Private Helper Methods
    
    @MainActor
    private func openSearchWindow(_ url: URL) async {
        #if os(macOS)
        HiskiWebViewManager.shared.openSearchResults(url: url)
        #endif
    }
    
    @MainActor
    private func openRecordWindow(_ url: URL) async {
        #if os(macOS)
        HiskiWebViewManager.shared.openRecordView(url: url)
        #endif
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
    
    private func buildBirthSearchUrl(session: String, name: String, date: String) throws -> URL {
        let params = [
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
            "ietunimi": "",
            "aetunimi": "",
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
