import Foundation
import XCTest

@testable import KalvianRootsCore

final class Phase9KustaaAcceptanceTests: XCTestCase {
  func testKustaaPromptProducesApprovedAsChildJuuretAndCanonicalHiskiOutputs() throws {
    let fixture = KustaaAcceptanceFixture()
    let juuret = try JuuretCitationService().generateJuuretCitation(
      context: fixture.context, selectedPerson: fixture.selected)

    XCTAssertEqual(juuret.renderedText, fixture.expectedJuuretCitation)
    XCTAssertEqual(juuret.sourceSpans.map(\.familyId), ["PIENI-PORKOLA 5"])

    let workup = try FamilyResearchService().prepareWorkup(
      comparison: fixture.comparison, context: fixture.context,
      juuretProposal: juuret, hiskiEvidence: [fixture.hiskiEvidence])
    let hiski = try XCTUnwrap(workup.hiskiCitationProposals.first)
    XCTAssertEqual(hiski.renderedText, fixture.expectedHiskiCitation)
    XCTAssertEqual(hiski.sourceURL, fixture.expectedHiskiCitation)
    XCTAssertTrue(hiski.requiresApproval)
  }

  func testParentCitationFailsWhenRequiredAsChildFamilyIsUnresolved() {
    let fixture = KustaaAcceptanceFixture()
    let incomplete = PersonContextResolution(
      contextId: "kustaa-incomplete", selectedPerson: fixture.selected,
      complete: false, families: [fixture.adultRecord],
      claims: fixture.context.claims.filter {
        $0.sourceSpan.familyId == "PIENI-PORKOLA 6"
      }, conflicts: [],
      missingReferences: [
        NetworkWarning(
          code: "family_validation_failed",
          message: "PIENI-PORKOLA 5 page references could not be validated.")
      ])

    XCTAssertThrowsError(
      try JuuretCitationService().generateJuuretCitation(
        context: incomplete, selectedPerson: fixture.selected)
    ) { error in
      XCTAssertEqual(
        error as? CitationServiceError,
        .asChildCitationRequired("Pieni-Porkola 5"))
    }
  }
}

private struct KustaaAcceptanceFixture {
  let selected: PersonReference
  let adultRecord: ParsedFamilyRecord
  let context: PersonContextResolution
  let comparison: FamilyComparisonRecord
  let hiskiEvidence: StoredHiskiEvidence

  let expectedHiskiCitation = "https://hiski.genealogia.fi/hiski?en+t4085059"
  let expectedJuuretCitation = """
    Information on pages 268, 269 includes:
    Matti Matinp., 22 December 1701 - 27 May 1764
    Brita Kustaant., 20 May 1699 - 25 November 1739
    m. 28 November 1725
    Children:
    → Kustaa, b. 22 August 1726, m. Kaarin Riippa 1748
    Matti, b. 1 January 1730, m. Liisa Nurila 1757
    Antti, b. 5 April 1734, m. Vappu Nurila 1755
    Brita, b. 2 May 1737, m. Elias Klapuri 1755
    Additional spouse:
    Kaarin Laurint., b. 1720 **
    m. 21 December 1740
    Children:
    Abraham, b. 28 December 1741
    Juho, b. 27 January 1744, m. Anna Lassila 1765 *
    Mikko, b. 1 October 1745, m. Liisa Lassila 1765
    Katariina, b. 22 November 1751, m. Pietari Juhonp. 1770
    Maria, b. 17 January 1756, m. Matti Pernu 1775
    Tuomas, b. 8 December 1759
    Additional spouse:
    Erik Matinp., b. 15 May 1721
    m. 5 April 1768
    Note:
    * Juho kuoli 26.01.1767, leski Pirkola 8.
    ** Vanhemmat Lauri Rahkonen, Maria Juhont., kuoli Porkolassa 15.09. -45 70-vuotiaana.
    """

  init() {
    let hash = String(repeating: "a", count: 64)
    let source = SourceRevision(
      sourceId: "fixture", fileName: canonicalRootsFileName, sha256: hash,
      byteCount: 1_000, loadedAt: "2026-08-20T23:29:26.000Z",
      canonicalMarkerValid: true)
    let adultSpan = SourceSpan(
      sourceId: source.sourceId, sourceSha256: hash, familyId: "PIENI-PORKOLA 6",
      pageReferences: ["269"], startLine: 20, endLine: 28,
      blockSha256: String(repeating: "b", count: 64))
    let childSpan = SourceSpan(
      sourceId: source.sourceId, sourceSha256: hash, familyId: "PIENI-PORKOLA 5",
      pageReferences: ["268-269"], startLine: 1, endLine: 19,
      blockSha256: String(repeating: "c", count: 64))
    selected = PersonReference(
      familyId: "PIENI-PORKOLA 6", coupleIndex: 0, role: .parent, personIndex: 0,
      rawName: "Kustaa", rawBirthDate: "22.08.1726", rawPatronymic: "Matinp.",
      familySearchId: "KLXK-37H")
    let matched = PersonReference(
      familyId: "PIENI-PORKOLA 5", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Kustaa", rawBirthDate: "22.08.1726", familySearchId: "KLXK-37H")
    let adult = Family(
      familyId: "PIENI-PORKOLA 6", pageReferences: ["269"],
      husband: Person(
        name: "Kustaa", patronymic: "Matinp.", birthDate: "22.08.1726",
        deathDate: "22.1.1811", asChild: "Pieni-Porkola 5", familySearchId: "KLXK-37H"),
      wife: Person(name: "Kaarin", patronymic: "Olavint.", birthDate: "02.11.1727"),
      marriageDate: "06.11.1748", children: [Person(name: "Margeta")])
    let childhood = Self.childhoodFamily()
    adultRecord = Self.record(adult, source: source, span: adultSpan)
    let childhoodRecord = Self.record(childhood, source: source, span: childSpan)
    let claims = [
      Self.claim(selected, "birthDate", "22.08.1726", adultSpan, .aiParsed),
      Self.claim(selected, "deathDate", "22.1.1811", adultSpan, .aiParsed),
      Self.claim(selected, "marriageDate", "06.11.1748", adultSpan, .aiParsed),
      Self.claim(selected, "birthDate", "22.08.1726", childSpan, .referenceHarvested),
      Self.claim(selected, "marriageDate", "48", childSpan, .referenceHarvested),
    ]
    let edge = FamilyReferenceEdge(
      fromFamilyId: "PIENI-PORKOLA 6", toFamilyId: "PIENI-PORKOLA 5",
      direction: .asChild, rawReference: "Pieni-Porkola 5", sourcePerson: selected,
      status: .resolved, matchedPerson: matched)
    context = PersonContextResolution(
      contextId: "kustaa-phase9-acceptance", selectedPerson: selected,
      complete: true, families: [adultRecord, childhoodRecord], edges: [edge],
      claims: claims, conflicts: [])
    comparison = FamilyComparisonRecord(
      comparisonId: "kustaa-comparison", contextId: context.contextId,
      selectedPerson: selected, startingFamilyId: adult.familyId,
      accessedFamilyIds: [adult.familyId, childhood.familyId], rows: [],
      matchCount: 0, familySearchOnlyCount: 0, juuretOnlyCount: 0,
      hiskiOnlyCount: 0, familySearchCandidateCount: 1,
      hiskiEvidenceIds: ["4085059"], conflicts: [], warnings: [],
      provenance: [adultSpan, childSpan])
    let motivation = HiskiQueryMotivation(
      person: selected, juuretField: "birthDate", juuretValue: "22.08.1726",
      sourceSpan: childSpan)
    let query = HiskiQuery(
      queryId: "kustaa-birth-query", eventType: .birth,
      requestedPrimaryName: "Kustaa", requestedSecondaryName: nil,
      requestedDate: "22.08.1726", parentBirthYear: nil,
      queryPrimaryName: "Kustaa", querySecondaryName: nil,
      queryDate: "22.08.1726", searchURL: "https://hiski.genealogia.fi/hiski?fixture",
      motivation: motivation)
    let candidate = HiskiResultCandidate(
      candidateId: "4085059", eventType: .birth,
      recordURL: "https://hiski.genealogia.fi/hiski?en+0053+kastetut+1",
      recordPath: "/hiski?en+0053+kastetut+1",
      fields: [
        HiskiResultField(label: "Born", value: "22.8.1726"),
        HiskiResultField(label: "Child", value: "Gustaf"),
      ], rowText: "22.8.1726 | Gustaf")
    let hiskiRecord = HiskiRecord(
      query: query, candidate: candidate, citationURL: expectedHiskiCitation,
      fields: candidate.fields,
      recordText: "Kälviä-Kelvi | born 22 August 1726 | child Gustaf",
      responseSha256: String(repeating: "d", count: 64))
    hiskiEvidence = StoredHiskiEvidence(
      candidateId: candidate.candidateId, query: query, candidate: candidate,
      searchResponseSha256: String(repeating: "e", count: 64),
      searchCandidateCount: 1, searchWasAmbiguous: false,
      searchRetrievedAt: "2026-08-20T23:23:40.000Z", record: hiskiRecord,
      recordRetrievedAt: "2026-08-20T23:23:41.000Z")
  }

  private static func childhoodFamily() -> Family {
    let matti = Person(
      name: "Matti", patronymic: "Matinp.", birthDate: "22.12.1701",
      deathDate: "27.05.1764")
    return Family(
      familyId: "PIENI-PORKOLA 5", pageReferences: ["268", "269"],
      couples: [
        Couple(
          husband: matti,
          wife: Person(
            name: "Brita", patronymic: "Kustaant.", birthDate: "20.05.1699",
            deathDate: "25.11.1739"),
          fullMarriageDate: "28.11.1725",
          children: [
            Person(
              name: "Kustaa", birthDate: "22.08.1726", marriageDate: "48",
              spouse: "Kaarin Riippa", familySearchId: "KLXK-37H"),
            Person(
              name: "Matti", birthDate: "01.01.1730", marriageDate: "57", spouse: "Liisa Nurila"),
            Person(
              name: "Antti", birthDate: "05.04.1734", marriageDate: "55", spouse: "Vappu Nurila"),
            Person(
              name: "Brita", birthDate: "02.05.1737", marriageDate: "55", spouse: "Elias Klapuri"),
          ], childrenDiedInfancy: 1),
        Couple(
          husband: matti,
          wife: Person(
            name: "Kaarin", patronymic: "Laurint.", birthDate: "1720",
            noteMarkers: ["**"]),
          fullMarriageDate: "21.12.1740",
          children: [
            Person(name: "Abraham", birthDate: "28.12.1741"),
            Person(
              name: "Juho", birthDate: "27.01.1744", marriageDate: "65",
              spouse: "Anna Lassila", noteMarkers: ["*"]),
            Person(
              name: "Mikko", birthDate: "01.10.1745", marriageDate: "65", spouse: "Liisa Lassila"),
            Person(
              name: "Katariina", birthDate: "22.11.1751", marriageDate: "70",
              spouse: "Pietari Juhonp."),
            Person(
              name: "Maria", birthDate: "17.01.1756", marriageDate: "75", spouse: "Matti Pernu"),
            Person(name: "Tuomas", birthDate: "08.12.1759"),
          ]),
        Couple(
          husband: matti,
          wife: Person(name: "Erik", patronymic: "Matinp.", birthDate: "15.05.1721"),
          fullMarriageDate: "05.04.1768", children: [], childrenDiedInfancy: 3),
      ], notes: [],
      noteDefinitions: [
        "*": "Juho kuoli 26.01.1767, leski Pirkola 8.",
        "**": "Vanhemmat Lauri Rahkonen, Maria Juhont., kuoli Porkolassa 15.09. -45 70-vuotiaana.",
      ])
  }

  private static func record(
    _ family: Family, source: SourceRevision, span: SourceSpan
  ) -> ParsedFamilyRecord {
    ParsedFamilyRecord(
      familyId: family.familyId, source: source, span: span,
      parserImplementationVersion: "acceptance-fixture", parsedFamily: family)
  }

  private static func claim(
    _ person: PersonReference, _ field: String, _ value: String,
    _ span: SourceSpan, _ derivation: ClaimDerivation
  ) -> FactClaim {
    FactClaim(
      claimId: "\(field)-\(value)-\(span.familyId)", subjectRef: person,
      field: field, value: value, sourceSpan: span,
      sourceFieldPath: "acceptance.\(field)", derivation: derivation,
      parserSchemaVersion: juuretFamilySchemaVersion,
      parserImplementationVersion: "acceptance-fixture")
  }
}
