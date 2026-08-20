import Foundation
import XCTest

@testable import KalvianRootsCore

final class FamilyNetworkServiceTests: XCTestCase {
  func testMariaContextHarvestsMarriageAndDeathWithProvenanceAndKeepsBirthConflict() async throws {
    let fixture = NetworkFixture.standard
    let service = fixture.service
    let maria = PersonReference(
      familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Maria", rawBirthDate: "03.03.1756", familySearchId: "KN1X-VHG"
    )

    let result = try await service.resolvePersonContext(
      person: maria, startingFamily: fixture.sakeri,
      limits: TraversalLimits(maxFamilies: 3, maxDepth: 3, maxElapsedSeconds: 10)
    )

    XCTAssertTrue(result.complete)
    XCTAssertEqual(result.families.map(\.familyId), ["SAKERI 4", "PUUKANGAS 6"])
    XCTAssertEqual(result.cycles, [["SAKERI 4", "PUUKANGAS 6", "SAKERI 4"]])
    XCTAssertEqual(result.externalServicesContacted, [])
    XCTAssertEqual(result.cacheStatuses, ["validated_hit"])

    let death = try XCTUnwrap(result.claims.first { $0.field == "deathDate" })
    XCTAssertEqual(death.value, "04.10.1829")
    XCTAssertEqual(death.derivation, .referenceHarvested)
    XCTAssertEqual(death.sourceSpan.familyId, "PUUKANGAS 6")
    XCTAssertEqual(death.sourceSpan.pageReferences, ["204"])
    XCTAssertEqual(death.sourceFieldPath, "couples[0].wife.deathDate")

    let marriages = result.claims.filter { $0.field == "marriageDate" }
    XCTAssertEqual(marriages.map(\.value), ["82", "26.12.1782"])
    XCTAssertFalse(result.conflicts.contains { $0.field == "marriageDate" })

    let birthConflict = try XCTUnwrap(result.conflicts.first { $0.field == "birthDate" })
    XCTAssertEqual(birthConflict.claims.map(\.value), ["03.03.1756", "13.03.1756"])
    XCTAssertEqual(
      birthConflict.claims.map { $0.sourceSpan.familyId }, ["SAKERI 4", "PUUKANGAS 6"])
  }

  func testFamilyTraversalReportsMissingReferenceWithoutGuessing() async throws {
    let fixture = NetworkFixture.standard
    var family = fixture.sakeri.parsedFamily
    family.couples[0].children = [
      Person(
        name: "Matti", birthDate: "01.01.1760", spouse: "Liisa",
        asParent: "MISSING 9"
      )
    ]
    let starting = fixture.record(family, pages: ["265"])

    let result = try await fixture.service.resolveFamilyReferences(
      startingFamily: starting,
      limits: TraversalLimits(maxFamilies: 4, maxDepth: 2, maxElapsedSeconds: 10)
    )

    XCTAssertTrue(result.complete)
    XCTAssertEqual(result.families.map(\.familyId), ["SAKERI 4"])
    XCTAssertEqual(result.edges.map(\.status), [.missing])
    XCTAssertEqual(result.missingReferences.map(\.code), ["missing_reference"])
    XCTAssertTrue(result.conflicts.isEmpty)
  }

  func testDepthLimitReturnsExplicitlyIncompleteResult() async throws {
    let fixture = NetworkFixture.standard

    let result = try await fixture.service.resolvePersonContext(
      person: PersonReference(
        familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
        rawName: "Maria"
      ),
      startingFamily: fixture.sakeri,
      limits: TraversalLimits(maxFamilies: 2, maxDepth: 0, maxElapsedSeconds: 10)
    )

    XCTAssertFalse(result.complete)
    XCTAssertEqual(result.families.count, 1)
    XCTAssertEqual(result.missingReferences.map(\.code), ["traversal_limit_reached"])
    XCTAssertTrue(result.conflicts.isEmpty)
  }

  func testContextIDIncludesTraversalLimits() async throws {
    let fixture = NetworkFixture.standard
    let person = PersonReference(
      familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Maria"
    )

    let shallow = try await fixture.service.resolvePersonContext(
      person: person, startingFamily: fixture.sakeri,
      limits: TraversalLimits(maxFamilies: 1, maxDepth: 0, maxElapsedSeconds: 10)
    )
    let expanded = try await fixture.service.resolvePersonContext(
      person: person, startingFamily: fixture.sakeri,
      limits: TraversalLimits(maxFamilies: 3, maxDepth: 3, maxElapsedSeconds: 10)
    )

    XCTAssertNotEqual(shallow.contextId, expanded.contextId)
  }

  func testReferenceRequiresRelationshipEvidenceAndDoesNotMatchByNameAlone() async throws {
    let fixture = NetworkFixture.standard
    var targetFamily = fixture.puukangas.parsedFamily
    targetFamily.couples[0].wife.birthDate = nil
    targetFamily.couples[0].wife.familySearchId = nil
    targetFamily.couples[0].husband.name = "Matti"
    let target = fixture.record(targetFamily, pages: ["204"])
    let service = FamilyNetworkService(
      bookTextService: StubBookText(records: [fixture.sakeri, target]),
      parsingService: StubNetworkParsing(records: [fixture.sakeri, target]),
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let result = try await service.resolvePersonContext(
      person: PersonReference(
        familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
        rawName: "Maria"
      ),
      startingFamily: fixture.sakeri,
      limits: TraversalLimits(maxFamilies: 2, maxDepth: 1, maxElapsedSeconds: 10)
    )

    XCTAssertEqual(result.missingReferences.map(\.code), ["reference_target_mismatch"])
    XCTAssertEqual(result.claims.filter { $0.derivation == .referenceHarvested }, [])
  }

  func testPersonReferenceIndexesDisambiguateRepeatedNamesAndValidateSuppliedBirthDate()
    async throws
  {
    let fixture = NetworkFixture.standard
    var family = fixture.sakeri.parsedFamily
    family.couples[0].children = [
      Person(name: "Maria", birthDate: "01.01.1791"),
      Person(name: "Maria", birthDate: "01.01.1793"),
    ]
    let starting = fixture.record(family, pages: ["265"])

    let selected = try await fixture.service.resolvePersonContext(
      person: PersonReference(
        familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 1,
        rawName: "Maria", rawBirthDate: "01.01.1793"
      ),
      startingFamily: starting,
      limits: TraversalLimits(maxFamilies: 1, maxDepth: 0, maxElapsedSeconds: 10)
    )
    XCTAssertEqual(selected.claims.first { $0.field == "birthDate" }?.value, "01.01.1793")

    do {
      _ = try await fixture.service.resolvePersonContext(
        person: PersonReference(
          familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 1,
          rawName: "Maria", rawBirthDate: "01.01.1791"
        ),
        startingFamily: starting,
        limits: TraversalLimits(maxFamilies: 1, maxDepth: 0, maxElapsedSeconds: 10)
      )
      XCTFail("Expected mismatched birth date to be rejected")
    } catch let error as FamilyNetworkError {
      XCTAssertEqual(error.code, "invalid_request")
    }
  }

  func testUnexpectedDuplicateIdentityAndFamilySearchIDAreReported() async throws {
    let fixture = NetworkFixture.standard
    var family = fixture.sakeri.parsedFamily
    family.couples[0].children = [
      Person(name: "Maria", birthDate: "01.01.1791", familySearchId: "SAME-ID"),
      Person(name: "Maria", birthDate: "01.01.1791", familySearchId: "SAME-ID"),
    ]
    let starting = fixture.record(family, pages: ["265"])

    let result = try await fixture.service.resolveFamilyReferences(
      startingFamily: starting,
      limits: TraversalLimits(maxFamilies: 1, maxDepth: 0, maxElapsedSeconds: 10)
    )

    XCTAssertEqual(
      Set(result.missingReferences.map(\.code)),
      Set(["duplicate_familysearch_id", "duplicate_person_identity"])
    )
  }

  func testAbbreviatedMarriageYearIsCompatibleAcrossCenturyBoundary() async throws {
    let fixture = NetworkFixture.standard
    var sourceFamily = fixture.sakeri.parsedFamily
    sourceFamily.couples[0].children[0].marriageDate = "00"
    var targetFamily = fixture.puukangas.parsedFamily
    targetFamily.couples[0].fullMarriageDate = "01.01.1800"
    let source = fixture.record(sourceFamily, pages: ["265"])
    let target = fixture.record(targetFamily, pages: ["204"])
    let service = FamilyNetworkService(
      bookTextService: StubBookText(records: [source, target]),
      parsingService: StubNetworkParsing(records: [source, target]),
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let result = try await service.resolvePersonContext(
      person: PersonReference(
        familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
        rawName: "Maria"
      ),
      startingFamily: source,
      limits: TraversalLimits(maxFamilies: 3, maxDepth: 2, maxElapsedSeconds: 10)
    )

    XCTAssertFalse(result.conflicts.contains { $0.field == "marriageDate" })
  }
}

private struct NetworkFixture {
  let sakeri: ParsedFamilyRecord
  let puukangas: ParsedFamilyRecord
  let service: FamilyNetworkService

  static var standard: NetworkFixture {
    let source = SourceRevision(
      sourceId: "test-source", fileName: canonicalRootsFileName,
      sha256: String(repeating: "a", count: 64), byteCount: 1000,
      loadedAt: "2026-08-19T00:00:00.000Z", canonicalMarkerValid: true
    )
    let sakeriFamily = Family(
      familyId: "SAKERI 4", pageReferences: ["265", "266"],
      husband: Person(name: "Antti", patronymic: "Mikonp.", birthDate: "05.08.1729"),
      wife: Person(name: "Brita", patronymic: "Juhont.", birthDate: "04.01.1735"),
      marriageDate: "08.10.1750",
      children: [
        Person(
          name: "Maria", birthDate: "03.03.1756", marriageDate: "82",
          spouse: "Juho Styrman", asParent: "PUUKANGAS 6", familySearchId: "KN1X-VHG"
        )
      ]
    )
    let puukangasFamily = Family(
      familyId: "PUUKANGAS 6", pageReferences: ["204"],
      couples: [
        Couple(
          husband: Person(name: "Juho", patronymic: "Juhonp.", birthDate: "03.09.1754"),
          wife: Person(
            name: "Maria", patronymic: "Antint.", birthDate: "13.03.1756",
            deathDate: "04.10.1829", asChild: "SAKERI 4", familySearchId: "KN1X-VHG"
          ),
          fullMarriageDate: "26.12.1782"
        )
      ]
    )
    let sakeri = makeRecord(sakeriFamily, source: source, pages: ["265", "266"], line: 100)
    let puukangas = makeRecord(puukangasFamily, source: source, pages: ["204"], line: 200)
    let book = StubBookText(records: [sakeri, puukangas])
    let parser = StubNetworkParsing(records: [sakeri, puukangas])
    return NetworkFixture(
      sakeri: sakeri, puukangas: puukangas,
      service: FamilyNetworkService(
        bookTextService: book, parsingService: parser,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
      )
    )
  }

  func record(_ family: Family, pages: [String]) -> ParsedFamilyRecord {
    Self.makeRecord(family, source: sakeri.source, pages: pages, line: 300)
  }

  private static func makeRecord(
    _ family: Family, source: SourceRevision, pages: [String], line: Int
  ) -> ParsedFamilyRecord {
    ParsedFamilyRecord(
      familyId: family.familyId, source: source,
      span: SourceSpan(
        sourceId: source.sourceId, sourceSha256: source.sha256, familyId: family.familyId,
        pageReferences: pages, startLine: line, endLine: line + 9,
        blockSha256: String(repeating: family.familyId == "SAKERI 4" ? "b" : "c", count: 64)
      ),
      parserImplementationVersion: "fixture-parser", parsedFamily: family
    )
  }
}

private actor StubNetworkParsing: FamilyParsingServing {
  private let records: [String: ParsedFamilyRecord]

  init(records: [ParsedFamilyRecord]) {
    self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.familyId.uppercased(), $0) })
  }

  func parseFamily(
    source: FamilyTextRecord, cachePolicy: ParseCachePolicy
  ) async throws -> ParsedFamilyRecord {
    guard let record = records[source.familyId.uppercased()] else {
      throw FamilyParsingError.cacheMiss(source.familyId)
    }
    return record
  }

  func getParsedFamily(
    familyId: String, sourceSHA256: String
  ) async throws -> ParsedFamilyRecord? {
    records[familyId.uppercased()]
  }
}

private struct StubBookText: BookTextServing {
  private let records: [String: ParsedFamilyRecord]

  init(records: [ParsedFamilyRecord]) {
    self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.familyId.uppercased(), $0) })
  }

  func loadSource() async throws -> SourceRevision {
    try XCTUnwrap(records.values.first?.source)
  }

  func getFamilyText(
    familyId: String, expectedSourceSHA256: String?
  ) async throws -> FamilyTextRecord {
    guard let record = records[familyId.uppercased()] else {
      throw BookTextError.familyNotFound(familyId)
    }
    if let expectedSourceSHA256, expectedSourceSHA256 != record.source.sha256 {
      throw BookTextError.sourceChanged(
        expected: expectedSourceSHA256, actual: record.source.sha256)
    }
    return FamilyTextRecord(
      familyId: record.familyId,
      rawText: "\(record.familyId), pages \(record.span.pageReferences.joined(separator: ","))",
      source: record.source, span: record.span
    )
  }
}
