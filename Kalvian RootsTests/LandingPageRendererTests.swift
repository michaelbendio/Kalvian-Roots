import XCTest
@testable import Kalvian_Roots

final class LandingPageRendererTests: XCTestCase {
    func testLandingPageShowsRemoteAccessPanelForTailscaleHost() {
        let html = HTMLRenderer.renderLandingPage(
            requestHost: "macbook.tailnet.ts.net:8081"
        )

        XCTAssertTrue(html.contains("Server / Remote Access"))
        XCTAssertTrue(html.contains("Kalvian Roots server is running on port 8081."))
        XCTAssertTrue(html.contains("remote browser"))
        XCTAssertTrue(html.contains("http://macbook.tailnet.ts.net:8081"))
        XCTAssertTrue(html.contains("http://macbook.tailnet.ts.net:8081/family/SAKERI%201/workup"))
        XCTAssertTrue(html.contains("Open Workup"))
    }

    func testLandingPageIdentifiesLocalHostAccess() {
        let html = HTMLRenderer.renderLandingPage(
            requestHost: "127.0.0.1:8081"
        )

        XCTAssertTrue(html.contains("local Mac browser"))
        XCTAssertTrue(html.contains("http://127.0.0.1:8081"))
    }

    func testLandingPageReturnKeyOpensReloadedFamilyPage() {
        let html = HTMLRenderer.renderLandingPage(
            requestHost: "127.0.0.1:8081"
        )

        XCTAssertTrue(html.contains(#"onsubmit="return openFamily(event)""#))
        XCTAssertTrue(html.contains("function familyURLFor(value)"))
        XCTAssertTrue(html.contains("'?reload=1'"))
        XCTAssertTrue(html.contains("window.location.href = familyURLFor(familyId);"))
        XCTAssertTrue(html.contains(#"<button type="submit">Open Family</button>"#))
    }
}
