import XCTest
#if os(macOS)
import AppKit
#endif
@testable import Kalvian_Roots

final class LandingPageRendererTests: XCTestCase {
    func testLandingPageUsesBookCoverWithOnlyFamilyInput() {
        let html = HTMLRenderer.renderLandingPage(
            requestHost: "macbook.tailnet.ts.net:8081"
        )

        XCTAssertTrue(html.contains(#"<main class="landing-page">"#))
        XCTAssertTrue(html.contains(#"<img class="landing-cover""#))
        XCTAssertTrue(html.contains(#"src="/assets/juuret-kalvialla-cover.jpg""#))
        XCTAssertTrue(html.contains(#"<form class="landing-form" method="GET" action="/family""#))
        XCTAssertTrue(html.contains(#"<label for="family">Enter Family ID</label>"#))
        XCTAssertTrue(html.contains(#"<input type="text" id="family" name="id""#))
        XCTAssertFalse(html.contains("Kalvian Roots Browser</h1>"))
        XCTAssertFalse(html.contains("Open Workup"))
        XCTAssertFalse(html.contains("Server / Remote Access"))
        XCTAssertFalse(html.contains("background-size: cover"))
    }

    func testLandingPageKeepsInvalidFamilyError() {
        let html = HTMLRenderer.renderLandingPage(
            error: "invalid",
            requestHost: "127.0.0.1:8081"
        )

        XCTAssertTrue(html.contains("Invalid family ID. Please check and try again."))
    }

    func testLandingPageReturnKeyOpensReloadedFamilyPage() {
        let html = HTMLRenderer.renderLandingPage(
            requestHost: "127.0.0.1:8081"
        )

        XCTAssertTrue(html.contains(#"onsubmit="return openFamily(event)""#))
        XCTAssertTrue(html.contains("function familyURLFor(value)"))
        XCTAssertTrue(html.contains("return '/family/' + encodeURIComponent(value)"))
        XCTAssertFalse(html.contains("composite=1"))
        XCTAssertFalse(html.contains("reload=1"))
        XCTAssertTrue(html.contains("window.location.href = familyURLFor(familyId);"))
        XCTAssertFalse(html.contains(#"<button type="submit">Open Family</button>"#))
    }

    func testServerRoutesLandingCoverAsset() throws {
        let server = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "Kalvian RootsTests/LandingPageRendererTests.swift",
                    with: "Kalvian Roots/Server/KalvianRootsServer.swift"
                ),
            encoding: .utf8
        )

        XCTAssertTrue(server.contains(#"case (.GET, "/assets/juuret-kalvialla-cover.jpg"):"#))
        XCTAssertTrue(server.contains("landingCoverAssetResponse()"))
        XCTAssertTrue(server.contains(#"contentType: "image/jpeg""#))
        XCTAssertTrue(server.contains("landingCoverJPEGData()"))
    }

    #if os(macOS)
    func testLandingCoverAssetIsBundled() {
        XCTAssertNotNil(NSImage(named: "JuuretCover"))
    }
    #endif
}
