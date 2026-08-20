import Foundation
import XCTest

@testable import KalvianRootsCore

final class JuuretCitationServiceTests: XCTestCase {
  func testSharedFormattingPreservesAppDateAndFootnoteRules() {
    XCTAssertEqual(
      JuuretCitationFormatting.date("07.12.81", parentBirthYear: 1760),
      "7 December 1781"
    )
    XCTAssertEqual(
      JuuretCitationFormatting.marriageDate("10", parentBirthYear: 1782),
      "1810"
    )
    XCTAssertEqual(JuuretCitationFormatting.footnoteMarker("★★"), "**")
    XCTAssertEqual(JuuretCitationFormatting.footnoteText("★★ Poika Abraham"), "** Poika Abraham")
    XCTAssertEqual(JuuretCitationFormatting.footnoteText("Text ★ retained"), "Text ★ retained")
  }

  func testMariaCitationUsesHarvestedFactsAndPreservesConflictAndProvenance() throws {
    let fixture = CitationFixture.maria

    let proposal = try JuuretCitationService().generateJuuretCitation(
      context: fixture.context,
      selectedPerson: fixture.maria
    )

    XCTAssertEqual(
      proposal.renderedText,
      """
      Information on pages 265, 266 includes:
      Antti Mikonp., 5 August 1729 - 14 March 1800
      Brita Juhont., 4 January 1735 - 4 December 1795
      m. 8 October 1750
      Children:
      → Maria, 3 March 1756 - 4 October 1829, m. Juho Styrman 26 December 1782
      Juho, b. 5 May 1758, m. Beata Marttila 1782
      Matti, b. 23 November 1759, m. Kaarin Riihimäki 1782
      Brita, b. 11 January 1764, m. Antti Marttila 1788
      Helena, b. 20 August 1767, m. Matti Siirilä 1790
      Mikko, b. 20 March 1770, m. Liisa Järvi 1795
      Kaarin, b. 22 July 1776, m. Antti Rita 1800
      Additional information:
      Maria's marriage and death dates are on page 204
      """
    )
    XCTAssertEqual(proposal.citationType, "juuret")
    XCTAssertTrue(proposal.requiresApproval)
    XCTAssertEqual(proposal.sourceSpans.map(\.familyId), ["SAKERI 4", "PUUKANGAS 6"])
    XCTAssertEqual(proposal.conflicts.map(\.field), ["birthDate"])
    XCTAssertEqual(proposal.conflicts[0].claims.map(\.value), ["03.03.1756", "13.03.1756"])
    XCTAssertEqual(
      proposal.warnings.map(\.code),
      ["cycle_detected", "unresolved_fact_conflicts"])
  }

  func testMissingDatesAndMultipleSpousesDoNotInventFacts() throws {
    let fixture = CitationFixture.multipleSpouses

    let proposal = try JuuretCitationService().generateJuuretCitation(
      context: fixture.context,
      selectedPerson: fixture.selected
    )

    XCTAssertEqual(
      proposal.renderedText,
      """
      Information on page 10 includes:
      → Matti
      Liisa
      Children:
      Anna
      Additional spouse:
      Kaarin, b. 1701
      m. 1720
      Children:
      Juho, b. 1721
      """
    )
    XCTAssertFalse(proposal.renderedText.contains("unknown"))
    XCTAssertTrue(proposal.conflicts.isEmpty)
  }

  func testSelectedPersonMustMatchStoredContextExactly() throws {
    let fixture = CitationFixture.maria
    let wrong = PersonReference(
      familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 1,
      rawName: "Juho"
    )

    XCTAssertThrowsError(
      try JuuretCitationService().generateJuuretCitation(
        context: fixture.context, selectedPerson: wrong)
    ) { error in
      XCTAssertEqual(error as? CitationServiceError, .selectedPersonMismatch)
    }
  }

  func testParentCitationUsesResolvedAsChildFamilyAndHarvestsAdultDeath() throws {
    let fixture = CitationFixture.parentAsChild

    let proposal = try JuuretCitationService().generateJuuretCitation(
      context: fixture.context, selectedPerson: fixture.selected)

    XCTAssertEqual(
      proposal.renderedText,
      """
      Information on page 2 includes:
      Erkki
      Kaarin
      Children:
      → Matti, 1700 - 1 January 1780
      Additional information:
      Matti's death date is on page 10
      """
    )
    XCTAssertEqual(proposal.selectedPerson, fixture.selected)
    XCTAssertEqual(proposal.sourceSpans.map(\.familyId), ["CHILD 1", "TEST 1"])
  }

  func testFileContextStoreRoundTripsWarningsAndCycles() async throws {
    let fixture = CitationFixture.maria
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = directory.appendingPathComponent("contexts.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = FilePersonContextStore(url: url)

    try await store.store(fixture.context)
    let restored = try await store.context(id: fixture.context.contextId)

    XCTAssertEqual(restored, fixture.context)
  }
}

private enum CitationFixture {
  struct MariaFixture {
    let maria: PersonReference
    let context: PersonContextResolution
  }

  struct MultipleSpousesFixture {
    let selected: PersonReference
    let context: PersonContextResolution
  }

  struct ParentAsChildFixture {
    let selected: PersonReference
    let context: PersonContextResolution
  }

  static var maria: MariaFixture {
    let source = revision()
    let sakeriSpan = span(
      source: source, familyId: "SAKERI 4", pages: ["265", "266"], marker: "b")
    let puukangasSpan = span(
      source: source, familyId: "PUUKANGAS 6", pages: ["204"], marker: "c")
    let maria = PersonReference(
      familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Maria", rawBirthDate: "03.03.1756", familySearchId: "KN1X-VHG"
    )
    let family = Family(
      familyId: "SAKERI 4", pageReferences: ["265", "266"],
      husband: Person(
        name: "Antti", patronymic: "Mikonp.", birthDate: "05.08.1729",
        deathDate: "14.03.1800"),
      wife: Person(
        name: "Brita", patronymic: "Juhont.", birthDate: "04.01.1735",
        deathDate: "04.12.1795"),
      marriageDate: "08.10.1750",
      children: [
        Person(
          name: "Maria", birthDate: "03.03.1756", marriageDate: "82",
          spouse: "Juho Styrman", asParent: "PUUKANGAS 6", familySearchId: "KN1X-VHG"),
        Person(name: "Juho", birthDate: "05.05.1758", marriageDate: "82", spouse: "Beata Marttila"),
        Person(
          name: "Matti", birthDate: "23.11.1759", marriageDate: "82", spouse: "Kaarin Riihimäki"),
        Person(
          name: "Brita", birthDate: "11.01.1764", marriageDate: "88", spouse: "Antti Marttila"),
        Person(
          name: "Helena", birthDate: "20.08.1767", marriageDate: "90", spouse: "Matti Siirilä"),
        Person(name: "Mikko", birthDate: "20.03.1770", marriageDate: "95", spouse: "Liisa Järvi"),
        Person(name: "Kaarin", birthDate: "22.07.1776", marriageDate: "00", spouse: "Antti Rita"),
      ]
    )
    let referenced = Family(
      familyId: "PUUKANGAS 6", pageReferences: ["204"],
      couples: [
        Couple(
          husband: Person(name: "Juho Styrman"),
          wife: Person(name: "Maria", birthDate: "13.03.1756", deathDate: "04.10.1829"),
          fullMarriageDate: "26.12.1782")
      ]
    )
    let records = [
      record(family, source: source, span: sakeriSpan),
      record(referenced, source: source, span: puukangasSpan),
    ]
    let birth = claim(
      maria, field: "birthDate", value: "03.03.1756", span: sakeriSpan,
      path: "couples[0].children[0].birthDate", derivation: .aiParsed)
    let shortMarriage = claim(
      maria, field: "marriageDate", value: "82", span: sakeriSpan,
      path: "couples[0].children[0].marriageDate", derivation: .aiParsed)
    let otherBirth = claim(
      maria, field: "birthDate", value: "13.03.1756", span: puukangasSpan,
      path: "couples[0].wife.birthDate", derivation: .referenceHarvested)
    let death = claim(
      maria, field: "deathDate", value: "04.10.1829", span: puukangasSpan,
      path: "couples[0].wife.deathDate", derivation: .referenceHarvested)
    let marriage = claim(
      maria, field: "marriageDate", value: "26.12.1782", span: puukangasSpan,
      path: "couples[0].fullMarriageDate", derivation: .referenceHarvested)
    let conflict = FactConflict(
      subjectRef: maria, field: "birthDate", reason: "source_values_disagree",
      claims: [birth, otherBirth])
    let context = PersonContextResolution(
      contextId: "context-maria", selectedPerson: maria, complete: true,
      families: records, claims: [birth, shortMarriage, otherBirth, death, marriage],
      conflicts: [conflict], cycles: [["SAKERI 4", "PUUKANGAS 6", "SAKERI 4"]]
    )
    return MariaFixture(maria: maria, context: context)
  }

  static var multipleSpouses: MultipleSpousesFixture {
    let source = revision()
    let sourceSpan = span(source: source, familyId: "TEST 1", pages: ["10"], marker: "d")
    let matti = Person(name: "Matti")
    let family = Family(
      familyId: "TEST 1", pageReferences: ["10"],
      couples: [
        Couple(husband: matti, wife: Person(name: "Liisa"), children: [Person(name: "Anna")]),
        Couple(
          husband: matti, wife: Person(name: "Kaarin", birthDate: "1701"),
          marriageDate: "1720", children: [Person(name: "Juho", birthDate: "1721")]),
      ]
    )
    let selected = PersonReference(
      familyId: "TEST 1", coupleIndex: 0, role: .parent, personIndex: 0,
      rawName: "Matti")
    let context = PersonContextResolution(
      contextId: "context-multiple", selectedPerson: selected, complete: true,
      families: [record(family, source: source, span: sourceSpan)], claims: [], conflicts: [])
    return MultipleSpousesFixture(selected: selected, context: context)
  }

  static var parentAsChild: ParentAsChildFixture {
    let source = revision()
    let adultSpan = span(source: source, familyId: "TEST 1", pages: ["10"], marker: "e")
    let childSpan = span(source: source, familyId: "CHILD 1", pages: ["2"], marker: "f")
    let adult = Family(
      familyId: "TEST 1", pageReferences: ["10"],
      husband: Person(name: "Matti", deathDate: "01.01.1780", asChild: "CHILD 1"),
      wife: Person(name: "Liisa"))
    let childhood = Family(
      familyId: "CHILD 1", pageReferences: ["2"],
      husband: Person(name: "Erkki"), wife: Person(name: "Kaarin"),
      children: [Person(name: "Matti", birthDate: "1700")])
    let selected = PersonReference(
      familyId: "TEST 1", coupleIndex: 0, role: .parent, personIndex: 0,
      rawName: "Matti")
    let matched = PersonReference(
      familyId: "CHILD 1", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Matti", rawBirthDate: "1700")
    let death = claim(
      selected, field: "deathDate", value: "01.01.1780", span: adultSpan,
      path: "couples[0].husband.deathDate", derivation: .aiParsed)
    let birth = claim(
      selected, field: "birthDate", value: "1700", span: childSpan,
      path: "couples[0].children[0].birthDate", derivation: .referenceHarvested)
    let edge = FamilyReferenceEdge(
      fromFamilyId: "TEST 1", toFamilyId: "CHILD 1", direction: .asChild,
      rawReference: "CHILD 1", sourcePerson: selected, status: .resolved,
      matchedPerson: matched)
    let context = PersonContextResolution(
      contextId: "context-parent", selectedPerson: selected, complete: true,
      families: [
        record(adult, source: source, span: adultSpan),
        record(childhood, source: source, span: childSpan),
      ],
      edges: [edge], claims: [death, birth], conflicts: [])
    return ParentAsChildFixture(selected: selected, context: context)
  }

  private static func revision() -> SourceRevision {
    SourceRevision(
      sourceId: "fixture", fileName: canonicalRootsFileName,
      sha256: String(repeating: "a", count: 64), byteCount: 1_000,
      loadedAt: "2026-08-19T00:00:00.000Z", canonicalMarkerValid: true)
  }

  private static func span(
    source: SourceRevision, familyId: String, pages: [String], marker: Character
  ) -> SourceSpan {
    SourceSpan(
      sourceId: source.sourceId, sourceSha256: source.sha256, familyId: familyId,
      pageReferences: pages, startLine: 1, endLine: 10,
      blockSha256: String(repeating: marker, count: 64))
  }

  private static func record(
    _ family: Family, source: SourceRevision, span: SourceSpan
  ) -> ParsedFamilyRecord {
    ParsedFamilyRecord(
      familyId: family.familyId, source: source, span: span,
      parserImplementationVersion: "fixture", parsedFamily: family)
  }

  private static func claim(
    _ person: PersonReference,
    field: String,
    value: String,
    span: SourceSpan,
    path: String,
    derivation: ClaimDerivation
  ) -> FactClaim {
    FactClaim(
      claimId: "\(field)-\(value)-\(span.familyId)", subjectRef: person,
      field: field, value: value, sourceSpan: span, sourceFieldPath: path,
      derivation: derivation, parserSchemaVersion: juuretFamilySchemaVersion,
      parserImplementationVersion: "fixture")
  }
}
