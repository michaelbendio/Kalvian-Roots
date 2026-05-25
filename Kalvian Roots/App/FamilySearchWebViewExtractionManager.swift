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
    @MainActor private var extractionTimeoutTask: Task<Void, Never>?
    @MainActor private var navigationContinuation: CheckedContinuation<Void, Error>?
    @MainActor private var detailsPageContinuation: CheckedContinuation<Void, Error>?
    @MainActor private var pendingDetailsPagePersonId: String?

    private let windowWidth: CGFloat = 1180
    private let windowHeight: CGFloat = 840
    private let extractionTimeoutNanoseconds: UInt64 = 90_000_000_000

    private struct TimeoutDiagnostics: Decodable {
        var url: String?
        var pageTitle: String?
        var extractionStage: String?
        var familyMembersSectionFound: Bool?
        var spousesAndChildrenSectionFound: Bool?
        var childrenMarkerCount: Int?
    }

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

    static func makeTimeoutExtractionPayload(
        expectedPersonId: String?,
        currentURL: String?,
        pageTitle: String? = nil,
        extractionStage: String? = nil,
        familyMembersSectionFound: Bool? = nil,
        spousesAndChildrenSectionFound: Bool? = nil,
        childrenMarkerCount: Int? = nil
    ) -> FamilySearchFamilyExtraction {
        let normalizedExpectedPersonId = expectedPersonId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let detectedPersonId = personIdFromDetailsURL(currentURL)
        let sourcePersonId = normalizedExpectedPersonId ?? detectedPersonId ?? ""
        let host = URLComponents(string: currentURL ?? "")?.host
        let lowercasedHost = host?.lowercased()
        let isFamilySearchPage = lowercasedHost == "familysearch.org"
            || lowercasedHost?.hasSuffix(".familysearch.org") == true

        var debugNotes = [
            "FamilySearch Swift WebKit timeout fired before the JavaScript message handler returned a result",
            "FamilySearch WebKit URL at Swift timeout: \(currentURL ?? "not open")"
        ]
        if let pageTitle, !pageTitle.isEmpty {
            debugNotes.append("FamilySearch WebKit title at Swift timeout: \(pageTitle)")
        }
        if let extractionStage, !extractionStage.isEmpty {
            debugNotes.append("FamilySearch extraction stage at Swift timeout: \(extractionStage)")
        } else {
            debugNotes.append("FamilySearch extraction stage at Swift timeout: unavailable because JavaScript timeout did not post")
        }

        return FamilySearchFamilyExtraction(
            sourcePersonId: sourcePersonId,
            parentFamilySearchId: sourcePersonId.isEmpty ? nil : sourcePersonId,
            extractedAt: ISO8601DateFormatter().string(from: Date()),
            sourceUrl: currentURL,
            focusPerson: nil,
            spouse: nil,
            marriage: nil,
            children: [],
            spouseGroups: [],
            status: "extractorTimeout",
            failureReason: "FamilySearch WebKit extraction timed out after 90 seconds without a result message.",
            url: currentURL,
            pageTitle: pageTitle,
            detectedHost: host,
            detectedPersonId: detectedPersonId,
            expectedPersonId: normalizedExpectedPersonId,
            isFamilySearchPage: isFamilySearchPage,
            isPersonDetailsPage: currentURL.flatMap { isDetailsPageURL($0, for: sourcePersonId) },
            familyMembersSectionFound: familyMembersSectionFound,
            spousesAndChildrenSectionFound: spousesAndChildrenSectionFound,
            childrenMarkerCount: childrenMarkerCount,
            rawCandidateChildCount: 0,
            spouseGroupCount: 0,
            childCount: 0,
            preferredChildCount: 0,
            debugNotes: debugNotes
        )
    }

    private static func personIdFromDetailsURL(_ urlString: String?) -> String? {
        guard let urlString,
              let components = URLComponents(string: urlString) else {
            return nil
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard let detailsIndex = parts.firstIndex(where: { $0.caseInsensitiveCompare("details") == .orderedSame }),
              detailsIndex + 1 < parts.count else {
            return nil
        }

        return parts[detailsIndex + 1].uppercased()
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

    @MainActor func openDetailsPageAndExtract(
        personId: String,
        log: ((String) -> Void)? = nil
    ) async throws -> FamilySearchFamilyExtraction {
        log?("FamilySearch WebKit extraction requested for: \(personId)")
        try await loadDetailsPage(personId: personId, log: log)
        log?("FamilySearch WebKit initial navigation finished: \(currentPageURLString())")
        log?("FamilySearch WebKit waiting for details page: \(personId)")
        try await waitForDetailsPage(personId: personId)
        log?("FamilySearch WebKit details page ready: \(currentPageURLString())")
        log?("FamilySearch WebKit DOM extraction started")
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
            startExtractionTimeout(expectedPersonId: expectedPersonId)

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

    @MainActor private func loadDetailsPage(
        personId: String,
        log: ((String) -> Void)? = nil
    ) async throws {
        let normalizedPersonId = personId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: FamilySearchDOMService.detailsURL(for: normalizedPersonId)) else {
            throw FamilySearchWebViewExtractionError.javascriptFailed("Invalid FamilySearch person ID.")
        }

        if webView?.url?.absoluteString == url.absoluteString {
            log?("FamilySearch WebKit already at target URL: \(url.absoluteString)")
            return
        }

        let webView = ensureWindow()
        window?.title = "FamilySearch \(normalizedPersonId)"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        log?("FamilySearch WebKit window visible: \(window?.isVisible == true ? "yes" : "no")")
        log?("FamilySearch WebKit navigation requested: \(url.absoluteString)")

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
        extractionTimeoutTask?.cancel()
        extractionTimeoutTask = nil

        switch result {
        case let .success(extraction):
            continuation.resume(returning: extraction)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    @MainActor private func startExtractionTimeout(expectedPersonId: String?) {
        extractionTimeoutTask?.cancel()
        let timeoutNanoseconds = extractionTimeoutNanoseconds
        extractionTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }

            guard let self,
                  self.extractionContinuation != nil else {
                return
            }

            let diagnostics = await self.collectTimeoutDiagnostics()
            let currentURL = diagnostics.url ?? self.webView?.url?.absoluteString
            self.finishExtraction(
                with: .success(
                    Self.makeTimeoutExtractionPayload(
                        expectedPersonId: expectedPersonId,
                        currentURL: currentURL,
                        pageTitle: diagnostics.pageTitle ?? self.webView?.title,
                        extractionStage: diagnostics.extractionStage,
                        familyMembersSectionFound: diagnostics.familyMembersSectionFound,
                        spousesAndChildrenSectionFound: diagnostics.spousesAndChildrenSectionFound,
                        childrenMarkerCount: diagnostics.childrenMarkerCount
                    )
                )
            )
        }
    }

    @MainActor private func collectTimeoutDiagnostics() async -> TimeoutDiagnostics {
        guard let webView else {
            return TimeoutDiagnostics()
        }

        let script = """
        (() => {
            function clean(text) {
                return (text || '').replace(/\\s+/g, ' ').trim();
            }

            const bodyText = document.body ? (document.body.innerText || '') : '';
            const lines = bodyText.split('\\n').map(clean).filter(Boolean);
            const familyIndex = lines.findIndex(line => /^Family Members$/i.test(line));
            const spousesIndex = lines.findIndex(line => /^Spouses and Children$/i.test(line));
            const parentsIndex = lines.findIndex((line, index) => index > spousesIndex && /^Parents and Siblings$/i.test(line));
            const sectionLines = spousesIndex >= 0
                ? lines.slice(spousesIndex + 1, parentsIndex >= 0 ? parentsIndex : lines.length)
                : [];

            return JSON.stringify({
                url: window.location.href,
                pageTitle: document.title,
                extractionStage: clean(window.__kalvianRootsFamilySearchStage),
                familyMembersSectionFound: familyIndex >= 0 || spousesIndex >= 0,
                spousesAndChildrenSectionFound: spousesIndex >= 0,
                childrenMarkerCount: sectionLines.filter(line => /^Children\\s*\\(\\d+\\)$/i.test(line)).length
            });
        })();
        """

        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let diagnostics = try? JSONDecoder().decode(TimeoutDiagnostics.self, from: data) else {
                    continuation.resume(returning: TimeoutDiagnostics())
                    return
                }

                continuation.resume(returning: diagnostics)
            }
        }
    }
}
#endif
