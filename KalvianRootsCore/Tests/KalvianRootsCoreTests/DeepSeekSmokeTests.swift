import Foundation
import XCTest
@testable import KalvianRootsCore

final class DeepSeekSmokeTests: XCTestCase {
  func testCurrentPromptProducesValidSakeri4WhenExplicitlyEnabled() async throws {
    guard ProcessInfo.processInfo.environment["RUN_DEEPSEEK_SMOKE"] == "1" else {
      return
    }
    let source = try await BookTextService().getFamilyText(
      familyId: "SAKERI 4", expectedSourceSHA256: nil
    )
    let response = try await DeepSeekFamilyClient().parseFamily(
      familyId: source.familyId, familyText: source.rawText
    )
    let family = try FamilyJSONDecoder.decode(response, expectedFamilyId: source.familyId)
    XCTAssertEqual(family.pageReferences, source.span.pageReferences)
    XCTAssertEqual(family.primaryCouple?.husband.displayName, "Antti Mikonp.")
    XCTAssertEqual(family.primaryCouple?.children.first?.name, "Maria")
  }
}
