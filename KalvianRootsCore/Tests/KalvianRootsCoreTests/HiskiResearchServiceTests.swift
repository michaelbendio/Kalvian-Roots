import Foundation
import XCTest

@testable import KalvianRootsCore

final class HiskiResearchServiceTests: XCTestCase {
  func testBuildsBirthMarriageAndDeathQueriesWithExistingRules() throws {
    let service = HiskiResearchService(fetcher: FixtureHiskiFetcher(responses: [:]))
    let motivation = fixtureMotivation()

    let birth = try service.buildQuery(
      eventType: .birth, primaryName: "Pietari Antinp.", date: "03.03.56",
      parentBirthYear: 1729, motivation: motivation)
    XCTAssertEqual(birth.requestedPrimaryName, "Pietari Antinp.")
    XCTAssertEqual(birth.queryPrimaryName, "Per")
    XCTAssertEqual(birth.queryDate, "3.3.1756")
    XCTAssertEqual(try queryValues(birth.searchURL)["kirja"], "kastetut")
    XCTAssertEqual(try queryValues(birth.searchURL)["etunimi"], "Per")

    let marriage = try service.buildQuery(
      eventType: .marriage, primaryName: "Juho Styrman", secondaryName: "Maria Antint.",
      date: "26.12.1782", motivation: motivation)
    XCTAssertEqual(try queryValues(marriage.searchURL)["kirja"], "vihityt")
    XCTAssertEqual(try queryValues(marriage.searchURL)["ietunimi"], "Juho")
    XCTAssertEqual(try queryValues(marriage.searchURL)["aetunimi"], "Maria")

    let death = try service.buildQuery(
      eventType: .death, primaryName: "Maria Antint. Styrman", date: "04.10.1829",
      motivation: motivation)
    XCTAssertEqual(try queryValues(death.searchURL)["kirja"], "haudatut")
    XCTAssertEqual(try queryValues(death.searchURL)["ietunimi"], "Maria")
    XCTAssertEqual(death.motivation.juuretField, "birthDate")
  }

  func testSavedBirthResultsRemainAmbiguousCandidatesAndPreserveNames() throws {
    let service = HiskiResearchService(fetcher: FixtureHiskiFetcher(responses: [:]))
    let query = try service.buildQuery(
      eventType: .birth, primaryName: "Maria", date: "03.03.1756",
      motivation: fixtureMotivation())
    let result = service.parseSavedResults(try fixture("hiski-birth-results", "html"), for: query)

    XCTAssertEqual(result.candidateCount, 2)
    XCTAssertTrue(result.ambiguous)
    XCTAssertEqual(result.candidates[0].recordPath, "/hiski?en+0265+kastetut+3326")
    XCTAssertEqual(result.candidates[0].fields.last?.label, "Child")
    XCTAssertEqual(result.candidates[0].fields.last?.value, "Maria")
    XCTAssertEqual(result.candidates[1].fields.last?.value, "Maria Elisabeta")
    XCTAssertTrue(result.candidates.allSatisfy { $0.recordURL.hasPrefix("https://hiski.genealogia.fi/hiski?") })
  }

  func testSavedMarriageAndDeathResultsUseSlGifAndPreserveReturnedText() throws {
    let service = HiskiResearchService(fetcher: FixtureHiskiFetcher(responses: [:]))
    let marriageQuery = try service.buildQuery(
      eventType: .marriage, primaryName: "Juho", secondaryName: "Maria",
      date: "26.12.1782", motivation: fixtureMotivation())
    let marriage = service.parseSavedResults(
      try fixture("hiski-marriage-results", "html"), for: marriageQuery)
    XCTAssertEqual(marriage.candidates.map(\.recordPath), ["/hiski?en+0265+vihityt+4421"])
    XCTAssertTrue(marriage.candidates[0].rowText.contains("Juho Styrman"))
    XCTAssertTrue(marriage.candidates[0].rowText.contains("Maria Antint."))

    let deathQuery = try service.buildQuery(
      eventType: .death, primaryName: "Maria", date: "4.10.1829",
      motivation: fixtureMotivation())
    let death = service.parseSavedResults(try fixture("hiski-death-results", "html"), for: deathQuery)
    XCTAssertEqual(death.candidateCount, 1)
    XCTAssertEqual(death.candidates[0].fields[3].value, "Maria Antint. Styrman")
  }

  func testDetailRecordUsesCanonicalCitationAndRetainsFields() async throws {
    let serviceWithoutNetwork = HiskiResearchService(fetcher: FixtureHiskiFetcher(responses: [:]))
    let query = try serviceWithoutNetwork.buildQuery(
      eventType: .birth, primaryName: "Maria", date: "3.3.1756",
      motivation: fixtureMotivation())
    let candidate = try XCTUnwrap(serviceWithoutNetwork.parseSavedResults(
      try fixture("hiski-birth-results", "html"), for: query).candidates.first)
    let fetcher = FixtureHiskiFetcher(responses: [
      candidate.recordURL: try fixture("hiski-record", "html")
    ])
    let record = try await HiskiResearchService(fetcher: fetcher).record(
      for: candidate, query: query, allowLiveNetwork: true)

    XCTAssertEqual(record.query.motivation, query.motivation)
    XCTAssertEqual(record.citationURL, "https://hiski.genealogia.fi/hiski?en+t4087076")
    XCTAssertEqual(record.fields.first?.label, "Born / Christened")
    XCTAssertEqual(record.fields.last?.value, "Maria")
    XCTAssertTrue(record.recordText.contains("Anders"))
  }

  func testLiveOperationsRequireExplicitOptIn() async throws {
    let service = HiskiResearchService(fetcher: FixtureHiskiFetcher(responses: [:]))
    let query = try service.buildQuery(
      eventType: .birth, primaryName: "Maria", date: "3.3.1756",
      motivation: fixtureMotivation())

    do {
      _ = try await service.search(query, allowLiveNetwork: false)
      XCTFail("Expected explicit live-network approval requirement")
    } catch {
      XCTAssertEqual(error as? HiskiResearchServiceError, .liveNetworkApprovalRequired)
    }
  }

  func testLiveSmokeWhenExplicitlyEnabledAndVPNReady() async throws {
    guard ProcessInfo.processInfo.environment["RUN_HISKI_SMOKE"] == "1" else { return }
    let service = HiskiResearchService()
    let query = try service.buildQuery(
      eventType: .birth, primaryName: "Maria", date: "3.3.1756",
      motivation: fixtureMotivation())
    let result = try await service.search(query, allowLiveNetwork: true)
    XCTAssertFalse(result.query.searchURL.isEmpty)
  }

  private func fixture(_ name: String, _ extensionName: String) throws -> String {
    let url = try XCTUnwrap(Bundle.module.url(
      forResource: "\(name).\(extensionName)", withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func queryValues(_ rawURL: String) throws -> [String: String] {
    let url = try XCTUnwrap(URL(string: rawURL))
    let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
  }
}

private struct FixtureHiskiFetcher: HiskiHTMLFetching {
  let responses: [String: String]

  func html(from url: URL) async throws -> String {
    guard let response = responses[url.absoluteString] else {
      throw HiskiResearchServiceError.invalidRequest("missing fixture")
    }
    return response
  }
}

private func fixtureMotivation() -> HiskiQueryMotivation {
  let revision = SourceRevision(
    sourceId: "juuret-local-documents", fileName: "JuuretKälviällä.roots",
    sha256: String(repeating: "a", count: 64), byteCount: 100,
    loadedAt: "2026-08-19T00:00:00Z", canonicalMarkerValid: true)
  let span = SourceSpan(
    sourceId: revision.sourceId, sourceSha256: revision.sha256,
    familyId: "SAKERI 4", pageReferences: ["265", "266"],
    startLine: 1, endLine: 10, blockSha256: String(repeating: "b", count: 64))
  return HiskiQueryMotivation(
    person: PersonReference(
      familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Maria", rawBirthDate: "03.03.1756"),
    juuretField: "birthDate", juuretValue: "03.03.1756", sourceSpan: span)
}
