import Foundation
import XCTest
@testable import KalvianRootsCore

final class EditorialCorrectionTests: XCTestCase {
  func testEditorialClaimsAreExcludedFromAIAndLegacyCannotReturnAfterReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try sourceRecord()
    let family = Family(familyId: "TEST 1", pageReferences: ["1"],
      husband: Person(name: "Simo", birthDate: "1710"),
      wife: Person(name: "Maria", birthDate: "n 1697", deathDate: "30.11.1764"))
    let response = String(data: try JSONEncoder().encode(family), encoding: .utf8)!
    let ai = EditorialRecordingAI(response: response)
    // A malformed legacy entry proves the corrected source never consults it.
    let legacy = directory.appendingPathComponent("legacy.json")
    try Data("broken legacy data".utf8).write(to: legacy)
    let native = directory.appendingPathComponent("native.json")
    let service = FamilyParsingService(ai: ai,
      nativeCache: NativeParsedFamilyCache(url: native), legacyCache: LegacyFamilyCacheReader(url: legacy))
    let record = try await service.parseFamily(source: source, cachePolicy: .useValidated)
    let inputs = await ai.inputs
    XCTAssertEqual(inputs, [JuuretEditorialSource(rawText: source.rawText)!.workingText])
    XCTAssertFalse(inputs[0].contains("Porkola 4"))
    XCTAssertNil(record.parsedFamily.primaryCouple?.wife.asChild)
    XCTAssertEqual(record.parsedFamily.editorialSource, JuuretEditorialSource(rawText: source.rawText))
    XCTAssertEqual(record.parserImplementationVersion, editorialFamilyParserVersion)

    var wrong = family
    wrong.couples[0].husband.birthDate = "n 1697"
    let wrongAI = EditorialRecordingAI(response: String(data: try JSONEncoder().encode(wrong), encoding: .utf8)!)
    let wrongParser = FamilyParsingService(ai: wrongAI,
      nativeCache: NativeParsedFamilyCache(url: directory.appendingPathComponent("wrong.json")),
      legacyCache: LegacyFamilyCacheReader(url: legacy))
    do {
      _ = try await wrongParser.parseFamily(source: source, cachePolicy: .refresh)
      XCTFail("A date borrowed from another source row must be rejected")
    } catch let error as FamilyParsingError {
      guard case .validationFailed = error else { return XCTFail("Unexpected \(error)") }
    }

    let reopened = FamilyParsingService(ai: EditorialRecordingAI(response: "must not run"),
      nativeCache: NativeParsedFamilyCache(url: native), legacyCache: LegacyFamilyCacheReader(url: legacy))
    let reloaded = try await reopened.parseFamily(source: source, cachePolicy: .cacheOnly)
    XCTAssertEqual(record, reloaded)
    let parent = PersonReference(familyId: "TEST 1", coupleIndex: 0, role: .parent,
      personIndex: 0, rawName: "Simo", rawBirthDate: "1710")
    let context = PersonContextResolution(contextId: "editorial-parent", selectedPerson: parent,
      complete: true, families: [reloaded], claims: [], conflicts: [], cycles: [])
    XCTAssertThrowsError(try JuuretCitationService().generateJuuretCitation(context: context, selectedPerson: parent)) {
      guard case CitationServiceError.asChildCitationRequired = $0 else { return XCTFail("Unexpected \($0)") }
    }
  }

  func testCorrectedChildProducesAttributedReviewDraftAndPreservesExactEvidence() throws {
    let source = try sourceRecord()
    var family = Family(familyId: "TEST 1", pageReferences: ["1"],
      husband: Person(name: "Lauri"), wife: Person(name: "Vappu"),
      children: [Person(name: "Maria", birthDate: "01.06.1714", familySearchId: "M8ZK-CC9")])
    family.editorialSource = JuuretEditorialSource(rawText: source.rawText)
    let record = ParsedFamilyRecord(familyId: "TEST 1", source: source.source, span: source.span,
      parserImplementationVersion: editorialFamilyParserVersion, parsedFamily: family)
    let person = PersonReference(familyId: "TEST 1", coupleIndex: 0, role: .child,
      personIndex: 0, rawName: "Maria", rawBirthDate: "01.06.1714", familySearchId: "M8ZK-CC9")
    let context = PersonContextResolution(contextId: "editorial-child", selectedPerson: person,
      complete: true, families: [record], claims: [], conflicts: [], cycles: [])
    let proposal = try JuuretCitationService().generateJuuretCitation(context: context, selectedPerson: person)
    XCTAssertTrue(proposal.renderedText.hasPrefix("REVIEW REQUIRED"))
    XCTAssertFalse(proposal.renderedText.contains("Information on page 1 includes:"))
    XCTAssertTrue(proposal.renderedText.contains(family.editorialSource!.correctionText))
    XCTAssertTrue(proposal.requiresApproval)
    XCTAssertEqual(proposal.warnings.map(\.code), ["editorial_review_required"])
    XCTAssertEqual(proposal, try JuuretCitationService().generateJuuretCitation(context: context, selectedPerson: person))
  }

  func testReferenceDelimitersDoNotBecomePartOfFamilyIdentifiers() throws {
    let family = Family(familyId: "TEST 1", pageReferences: ["1"],
      husband: Person(name: "Simo", asChild: "{Tikkanen 1}"), wife: Person(name: "Maria"),
      children: [Person(name: "Lauri", asParent: "{Porkola 2}")])
    let json = String(data: try JSONEncoder().encode(family), encoding: .utf8)!
    let parsed = try FamilyJSONDecoder.decode(json, expectedFamilyId: "TEST 1")
    XCTAssertEqual(parsed.primaryCouple?.husband.asChild, "Tikkanen 1")
    XCTAssertEqual(parsed.primaryCouple?.children.first?.asParent, "Porkola 2")
  }

  private func sourceRecord() throws -> FamilyTextRecord {
    try BookTextSnapshot(data: Data("""
    canonical
    TEST 1, page 1
    ★ 1710 Simo
    ★ n 1697 Maria † 30.11.1764
    Research correction, 2026-09-11 (editorial; manual citation review required):
    The book claims Porkola 4. That parent reference is withdrawn.
    Death evidence: https://hiski.genealogia.fi/hiski?en+t4076945
    """.utf8), fileName: canonicalRootsFileName, sourceId: "test").familyText(familyId: "TEST 1")
  }
}

private actor EditorialRecordingAI: FamilyAIResponding {
  var inputs: [String] = []
  let response: String
  init(response: String) { self.response = response }
  func parseFamily(familyId: String, familyText: String) async throws -> String {
    inputs.append(familyText)
    return response
  }
}
