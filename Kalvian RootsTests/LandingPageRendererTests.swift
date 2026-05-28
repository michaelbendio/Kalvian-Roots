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
}
