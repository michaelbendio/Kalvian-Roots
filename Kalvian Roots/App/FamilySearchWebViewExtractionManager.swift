//
//  FamilySearchWebViewExtractionManager.swift
//  Kalvian Roots
//
//  User-visible FamilySearch extraction window backed by WKWebView.
//

import Foundation

#if os(macOS)
import AppKit
import WebKit

enum FamilySearchWebViewExtractionError: LocalizedError {
    case pageNotOpen
    case extractionAlreadyRunning
    case javascriptFailed(String)
    case invalidMessage
    case decodeFailed(String)
    case windowClosed

    var errorDescription: String? {
        switch self {
        case .pageNotOpen:
            return "Open the FamilySearch page in Kalvian Roots, sign in if needed, then extract again."
        case .extractionAlreadyRunning:
            return "FamilySearch extraction is already running."
        case let .javascriptFailed(message):
            return "FamilySearch extraction JavaScript failed: \(message)"
        case .invalidMessage:
            return "FamilySearch extraction returned an invalid message."
        case let .decodeFailed(message):
            return "FamilySearch extraction could not be decoded: \(message)"
        case .windowClosed:
            return "FamilySearch extraction window was closed."
        }
    }
}

final class FamilySearchWebViewExtractionManager: NSObject, WKNavigationDelegate, NSWindowDelegate, WKScriptMessageHandler {
    @MainActor static let shared = FamilySearchWebViewExtractionManager()

    @MainActor private var window: NSWindow?
    @MainActor private var webView: WKWebView?
    @MainActor private var extractionContinuation: CheckedContinuation<FamilySearchFamilyExtraction, Error>?
    @MainActor private var navigationContinuation: CheckedContinuation<Void, Error>?
    @MainActor private var detailsPageContinuation: CheckedContinuation<Void, Error>?
    @MainActor private var pendingDetailsPagePersonId: String?

    private let windowWidth: CGFloat = 1180
    private let windowHeight: CGFloat = 840

    static func isDetailsPageURL(_ urlString: String?, for personId: String) -> Bool {
        guard let urlString,
              let components = URLComponents(string: urlString),
              let host = components.host?.lowercased() else {
            return false
        }

        guard host == "www.familysearch.org" || host == "familysearch.org" else {
            return false
        }

        let normalizedPath = components.path.uppercased()
        let normalizedPersonId = personId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalizedPath.contains("/TREE/PERSON/DETAILS/")
            && normalizedPath.contains(normalizedPersonId)
    }

    @MainActor private override init() {
        super.init()
    }

    @MainActor func openDetailsPage(personId: String) {
        let normalizedPersonId = personId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: FamilySearchDOMService.detailsURL(for: normalizedPersonId)) else {
            return
        }

        let webView = ensureWindow()
        window?.title = "FamilySearch \(normalizedPersonId)"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: url))
    }

    @MainActor func openDetailsPageAndExtract(personId: String) async throws -> FamilySearchFamilyExtraction {
        try await loadDetailsPage(personId: personId)
        try await waitForDetailsPage(personId: personId)
        return try await extractCurrentDetailsPage(expectedPersonId: personId)
    }

    @MainActor func currentPageURLString() -> String {
        webView?.url?.absoluteString ?? "not open"
    }

    @MainActor func openFamilySearchHome() {
        guard let url = URL(string: "https://www.familysearch.org/en/tree/") else {
            return
        }

        let webView = ensureWindow()
        window?.title = "FamilySearch"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: url))
    }

    @MainActor func extractCurrentDetailsPage(expectedPersonId: String? = nil) async throws -> FamilySearchFamilyExtraction {
        guard let webView else {
            if let expectedPersonId {
                return try await openDetailsPageAndExtract(personId: expectedPersonId)
            }

            openFamilySearchHome()
            throw FamilySearchWebViewExtractionError.pageNotOpen
        }

        guard extractionContinuation == nil else {
            throw FamilySearchWebViewExtractionError.extractionAlreadyRunning
        }

        if let expectedPersonId, !isLoadedDetailsPage(for: expectedPersonId) {
            try await loadDetailsPage(personId: expectedPersonId)
            try await waitForDetailsPage(personId: expectedPersonId)
        }

        let script = expectedPersonId.map(FamilySearchDOMService.makeWebKitExtractionScript)
            ?? FamilySearchDOMService.makeWebKitExtractionScriptForCurrentPage()

        return try await withCheckedThrowingContinuation { continuation in
            extractionContinuation = continuation

            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let error else {
                    return
                }

                Task { @MainActor in
                    self?.finishExtraction(
                        with: .failure(
                            FamilySearchWebViewExtractionError.javascriptFailed(error.localizedDescription)
                        )
                    )
                }
            }
        }
    }

    @MainActor
    @discardableResult
    private func ensureWindow() -> WKWebView {
        if let webView, let window, window.isVisible {
            return webView
        }

        let userContentController = WKUserContentController()
        userContentController.add(self, name: FamilySearchDOMService.webKitExtractionMessageHandler)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight), configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 140, y: 120, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FamilySearch"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        return webView
    }

    @MainActor private func loadDetailsPage(personId: String) async throws {
        let normalizedPersonId = personId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: FamilySearchDOMService.detailsURL(for: normalizedPersonId)) else {
            throw FamilySearchWebViewExtractionError.javascriptFailed("Invalid FamilySearch person ID.")
        }

        if webView?.url?.absoluteString == url.absoluteString {
            return
        }

        let webView = ensureWindow()
        window?.title = "FamilySearch \(normalizedPersonId)"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation?.resume(throwing: FamilySearchWebViewExtractionError.windowClosed)
            navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    @MainActor private func waitForDetailsPage(personId: String) async throws {
        let normalizedPersonId = personId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedPersonId.isEmpty else {
            return
        }

        if isLoadedDetailsPage(for: normalizedPersonId) {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            detailsPageContinuation?.resume(throwing: FamilySearchWebViewExtractionError.windowClosed)
            pendingDetailsPagePersonId = normalizedPersonId
            detailsPageContinuation = continuation
            pollForDetailsPage(personId: normalizedPersonId)
        }
    }

    @MainActor private func isLoadedDetailsPage(for personId: String) -> Bool {
        Self.isDetailsPageURL(webView?.url?.absoluteString, for: personId)
    }

    @MainActor private func pollForDetailsPage(personId: String) {
        Task { @MainActor [weak self] in
            while let self,
                  self.detailsPageContinuation != nil,
                  self.pendingDetailsPagePersonId == personId {
                self.resumeDetailsPageContinuationIfLoaded()
                if self.detailsPageContinuation == nil {
                    return
                }

                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    @MainActor private func resumeDetailsPageContinuationIfLoaded() {
        guard let pendingPersonId = pendingDetailsPagePersonId,
              isLoadedDetailsPage(for: pendingPersonId) else {
            return
        }

        detailsPageContinuation?.resume()
        detailsPageContinuation = nil
        pendingDetailsPagePersonId = nil
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            self.handleExtractionMessage(message.body)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard webView === self.webView else {
                return
            }

            if let url = webView.url?.absoluteString {
                self.window?.title = "FamilySearch - \(url)"
            }

            self.navigationContinuation?.resume()
            self.navigationContinuation = nil

            self.resumeDetailsPageContinuationIfLoaded()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard webView === self.webView else {
                return
            }

            self.navigationContinuation?.resume(
                throwing: FamilySearchWebViewExtractionError.javascriptFailed(error.localizedDescription)
            )
            self.navigationContinuation = nil
            self.detailsPageContinuation?.resume(
                throwing: FamilySearchWebViewExtractionError.javascriptFailed(error.localizedDescription)
            )
            self.detailsPageContinuation = nil
            self.pendingDetailsPagePersonId = nil
        }
    }

    @MainActor func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }

        finishExtraction(with: .failure(FamilySearchWebViewExtractionError.windowClosed))
        navigationContinuation?.resume(throwing: FamilySearchWebViewExtractionError.windowClosed)
        navigationContinuation = nil
        detailsPageContinuation?.resume(throwing: FamilySearchWebViewExtractionError.windowClosed)
        detailsPageContinuation = nil
        pendingDetailsPagePersonId = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: FamilySearchDOMService.webKitExtractionMessageHandler
        )
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
    }

    @MainActor private func handleExtractionMessage(_ body: Any) {
        guard let json = body as? String,
              let data = json.data(using: .utf8) else {
            finishExtraction(with: .failure(FamilySearchWebViewExtractionError.invalidMessage))
            return
        }

        do {
            let extraction = try JSONDecoder().decode(FamilySearchFamilyExtraction.self, from: data)
            finishExtraction(with: .success(extraction))
        } catch {
            finishExtraction(with: .failure(FamilySearchWebViewExtractionError.decodeFailed(error.localizedDescription)))
        }
    }

    @MainActor private func finishExtraction(with result: Result<FamilySearchFamilyExtraction, Error>) {
        guard let continuation = extractionContinuation else {
            return
        }

        extractionContinuation = nil

        switch result {
        case let .success(extraction):
            continuation.resume(returning: extraction)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
#endif
