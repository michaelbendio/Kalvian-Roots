import Foundation
import XCTest

@testable import KalvianRootsCore

final class FamilyComparisonTests: XCTestCase {
  private let names = BuiltinNameEquivalenceManager()

  func testIdentityRequiresEquivalentNameAndExactBirthDate() {
    let liisa = candidate("Liisa", "1.2.1791", .juuretKalvialla)
    let elisabet = candidate("Elisabet", "01.02.1791", .hiski)
    let laterMaria = candidate("Maria", "1.2.1793", .familySearch)
    let earlierMaria = candidate("Maria", "1.2.1791", .juuretKalvialla)

    XCTAssertTrue(liisa.identity.matches(elisabet.identity))
    XCTAssertFalse(laterMaria.identity.matches(earlierMaria.identity))
    XCTAssertEqual(liisa.rawName, "Liisa")
    XCTAssertEqual(elisabet.rawName, "Elisabet")
  }

  func testUndatedPersonNeverMatchesByNameAlone() {
    let familySearch = candidate("Maria", nil, .familySearch)
    let juuret = candidate("Maria", "3.3.1756", .juuretKalvialla)
    let result = FamilyComparisonResult(
      familySearch: [familySearch], juuretKalvialla: [juuret], hiski: [])

    XCTAssertEqual(result.matches.count, 0)
    XCTAssertEqual(result.familySearchOnly.count, 1)
    XCTAssertEqual(result.juuretOnly.count, 1)
  }

  func testRowsAreDeterministicForRepeatedNames() {
    let people = [
      candidate("Maria", "1.1.1793", .juuretKalvialla),
      candidate("Maria", "1.1.1791", .juuretKalvialla),
    ]
    let result = FamilyComparisonResult(
      familySearch: [], juuretKalvialla: people, hiski: [])

    XCTAssertEqual(result.rows.compactMap { GenealogyDateParser.normalized($0.identity.birthDate) }, [
      "1791-01-01", "1793-01-01",
    ])
  }

  func testResearchFileStoresRoundTripAndRejectCorruption() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("KalvianResearchStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let span = SourceSpan(
      sourceId: "fixture", sourceSha256: String(repeating: "a", count: 64),
      familyId: "SAKERI 4", pageReferences: ["265", "266"], startLine: 1, endLine: 2,
      blockSha256: String(repeating: "b", count: 64))
    let person = PersonReference(
      familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Maria", rawBirthDate: "03.03.1756")
    let motivation = HiskiQueryMotivation(
      person: person, juuretField: "birthDate", juuretValue: "03.03.1756",
      sourceSpan: span)
    let query = try HiskiResearchService().buildQuery(
      eventType: .birth, primaryName: "Maria", secondaryName: nil,
      date: "03.03.1756", parentBirthYear: nil, motivation: motivation)
    let candidate = HiskiResultCandidate(
      candidateId: "candidate-1", eventType: .birth,
      recordURL: "https://hiski.genealogia.fi/hiski?en+0265+kastetut+3326",
      recordPath: "/hiski?en+0265+kastetut+3326",
      fields: [HiskiResultField(label: "Born", value: "3.3.1756"),
        HiskiResultField(label: "Child", value: "Maria")], rowText: "3.3.1756 | Maria")
    let search = HiskiSearchResult(
      query: query, candidates: [candidate], responseSha256: String(repeating: "c", count: 64))
    let evidenceURL = directory.appendingPathComponent("evidence.json")
    let evidenceStore = FileHiskiEvidenceStore(url: evidenceURL)
    try await evidenceStore.store(searchResult: search, retrievedAt: "2026-08-20T00:00:00Z")
    let storedEvidence = try await evidenceStore.evidence(candidateId: "candidate-1")
    XCTAssertEqual(storedEvidence?.candidate, candidate)

    let comparison = FamilyComparisonRecord(
      comparisonId: "comparison-1", contextId: "context-1", selectedPerson: person,
      startingFamilyId: "SAKERI 4", accessedFamilyIds: ["SAKERI 4"], rows: [],
      matchCount: 0, familySearchOnlyCount: 0, juuretOnlyCount: 0, hiskiOnlyCount: 0,
      familySearchCandidateCount: 0, hiskiEvidenceIds: ["candidate-1"], conflicts: [],
      warnings: [], provenance: [span])
    let comparisonStore = FileFamilyComparisonStore(
      url: directory.appendingPathComponent("comparisons.json"))
    try await comparisonStore.store(comparison)
    let storedComparison = try await comparisonStore.comparison(id: "comparison-1")
    XCTAssertEqual(storedComparison, comparison)

    let corruptURL = directory.appendingPathComponent("corrupt.json")
    try Data("not json".utf8).write(to: corruptURL)
    let corruptStore = FileHiskiEvidenceStore(url: corruptURL)
    do {
      _ = try await corruptStore.evidence(candidateId: "candidate-1")
      XCTFail("Expected corrupt research cache to fail loudly")
    } catch let error as ResearchStoreError {
      XCTAssertEqual(error.code, "cache_unavailable")
    }
  }

  private func candidate(
    _ name: String, _ date: String?, _ source: PersonCandidate.SourceType
  ) -> PersonCandidate {
    PersonCandidate(
      name: name, birthDate: GenealogyDateParser.parse(date), rawBirthDate: date,
      source: source, nameManager: names)
  }
}
