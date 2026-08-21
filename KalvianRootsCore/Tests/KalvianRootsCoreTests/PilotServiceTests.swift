import Foundation
import Testing
@testable import KalvianRootsCore

private actor PilotWorker: TraversalWorkProcessing {
  func process(
    familyId: String, sourceSHA256: String, budget: TraversalBudget
  ) -> TraversalWorkResult {
    TraversalWorkResult(
      sourceSpan: pilotSpan(familyId),
      referencedFamilyIds: familyId == "A 1" ? ["B 1"] : [])
  }
}

@Suite("Pilot service")
struct PilotServiceTests {
  @Test("pilot measures known outcomes and leaves unsupported quality claims pending")
  func metricsAreEvidenceBounded() async throws {
    let fixture = try await makePilotFixture(recordApproval: true)
    let report = try await fixture.service.create(definition: fixture.definition)

    #expect(report.completedFamilyIds == ["A 1", "B 1"])
    #expect(report.incompleteFamilies.isEmpty)
    #expect(report.readiness == .pending)
    #expect(report.broaderTraversalBlocked)
    #expect(report.metrics.first { $0.code == "family_completion" }?.value == 1)
    #expect(report.metrics.first { $0.code == "citation_quality" }?.value == 1)
    #expect(report.metrics.first { $0.code == "parsing_accuracy" }?.status == .pendingHumanReview)
    #expect(report.metrics.first { $0.code == "ai_cost" }?.status == .unavailable)
    #expect(report.unresolvedConflictFields["birthDate"] == 1)
  }

  @Test("readiness remains blocked until an explicit human decision is recorded")
  func readinessRequiresHumanDecision() async throws {
    let fixture = try await makePilotFixture(recordApproval: false)
    let report = try await fixture.service.create(definition: fixture.definition)

    await #expect(throws: PilotServiceError.explicitConfirmationRequired) {
      try await fixture.service.recordReadiness(
        pilotId: report.pilotId, readiness: .ready, note: "Proceed",
        explicitHumanConfirmation: false)
    }
    let decided = try await fixture.service.recordReadiness(
      pilotId: report.pilotId, readiness: .notReady,
      note: "Complete supervised citation review first.", explicitHumanConfirmation: true)
    #expect(decided.readiness == .notReady)
    #expect(decided.broaderTraversalBlocked)
    #expect(decided.readinessHistory.count == 1)
  }

  @Test("an unfinished pilot family remains visible with a reason")
  func incompleteFamilyIsVisible() async throws {
    let traversalService = TraversalSessionService(
      worker: PilotWorker(), store: MemoryTraversalSessionStore(), now: { pilotDate })
    let traversal = try await traversalService.start(
      startingFamilyIds: ["A 1"], sourceSHA256: pilotHash,
      policy: TraversalPolicy(
        maxFamilies: 2, maxDepth: 1, maxItemsPerResume: 1,
        allowedFamilyIds: ["A 1", "B 1"]))
    _ = try await traversalService.resume(sessionId: traversal.sessionId)
    let reviewService = CitationReviewService(store: MemoryCitationReviewStore())
    let service = PilotService(
      traversalService: traversalService, citationReviewService: reviewService,
      store: MemoryPilotReportStore(), now: { pilotDate })
    let report = try await service.create(definition: PilotDefinition(
      name: "unfinished", familyIds: ["A 1", "B 1"],
      traversalSessionId: traversal.sessionId, citationReviewIds: []))

    #expect(report.completedFamilyIds == ["A 1"])
    #expect(report.incompleteFamilies["B 1"]?.contains("not completed") == true)
    #expect(report.metrics.first { $0.code == "family_completion" }?.value == 0.5)
  }

  @Test("file pilot reports survive a new store instance")
  func fileStoreIsDurable() async throws {
    let fixture = try await makePilotFixture(recordApproval: true)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("reports-v1.json")
    let first = PilotService(
      traversalService: fixture.traversalService,
      citationReviewService: fixture.citationReviewService,
      store: FilePilotReportStore(url: url), now: { pilotDate })
    let saved = try await first.create(definition: fixture.definition)

    let second = PilotService(
      traversalService: fixture.traversalService,
      citationReviewService: fixture.citationReviewService,
      store: FilePilotReportStore(url: url), now: { pilotDate })
    let restored = try await second.get(pilotId: saved.pilotId)
    #expect(restored == saved)
  }
}

private struct PilotFixture {
  let service: PilotService
  let definition: PilotDefinition
  let traversalService: TraversalSessionService
  let citationReviewService: CitationReviewService
}

private func makePilotFixture(recordApproval: Bool) async throws -> PilotFixture {
  let traversalService = TraversalSessionService(
    worker: PilotWorker(), store: MemoryTraversalSessionStore(), now: { pilotDate })
  let started = try await traversalService.start(
    startingFamilyIds: ["A 1"], sourceSHA256: pilotHash,
    policy: TraversalPolicy(
      maxFamilies: 2, maxDepth: 1, maxItemsPerResume: 1,
      allowedFamilyIds: ["A 1", "B 1"]))
  _ = try await traversalService.resume(sessionId: started.sessionId)
  _ = try await traversalService.resume(sessionId: started.sessionId)

  let reviewService = CitationReviewService(
    store: MemoryCitationReviewStore(), now: { pilotDate })
  var review = try await reviewService.prepare(workup: pilotWorkup())
  if recordApproval {
    review = try await reviewService.recordDecision(
      reviewId: review.reviewId, proposalId: review.items[0].proposal.proposalId,
      disposition: .approved, note: "Pilot review", explicitHumanConfirmation: true)
  }
  let service = PilotService(
    traversalService: traversalService, citationReviewService: reviewService,
    store: MemoryPilotReportStore(), now: { pilotDate })
  return PilotFixture(
    service: service,
    definition: PilotDefinition(
      name: "two-family pilot", familyIds: ["A 1", "B 1"],
      traversalSessionId: started.sessionId, citationReviewIds: [review.reviewId]),
    traversalService: traversalService, citationReviewService: reviewService)
}

private func pilotWorkup() -> FamilyResearchWorkup {
  let span = pilotSpan("A 1")
  let source = SourceRevision(
    sourceId: "fixture", fileName: canonicalRootsFileName, sha256: pilotHash,
    byteCount: 100, loadedAt: "2027-01-15T08:00:00.000Z", canonicalMarkerValid: true)
  let person = PersonReference(
    familyId: "A 1", coupleIndex: 0, role: .child, personIndex: 0,
    rawName: "Maria", rawBirthDate: "01.01.1800")
  let parsed = ParsedFamilyRecord(
    familyId: "A 1", source: source, span: span, parserImplementationVersion: "fixture",
    parsedFamily: Family(
      familyId: "A 1", pageReferences: ["1"], husband: Person(name: "Father"),
      wife: Person(name: "Mother"), children: [Person(name: "Maria")]))
  let claim1 = FactClaim(
    claimId: "claim-1", subjectRef: person, field: "birthDate", value: "01.01.1800",
    sourceSpan: span, sourceFieldPath: "children[0].birthDate", derivation: .aiParsed,
    parserSchemaVersion: juuretFamilySchemaVersion, parserImplementationVersion: "fixture")
  let claim2 = FactClaim(
    claimId: "claim-2", subjectRef: person, field: "birthDate", value: "02.01.1800",
    sourceSpan: span, sourceFieldPath: "referenced.birthDate", derivation: .referenceHarvested,
    parserSchemaVersion: juuretFamilySchemaVersion, parserImplementationVersion: "fixture")
  let conflict = FactConflict(
    subjectRef: person, field: "birthDate", reason: "fixture disagreement",
    claims: [claim1, claim2])
  let comparison = FamilyComparisonRecord(
    comparisonId: "pilot-comparison", contextId: "pilot-context", selectedPerson: person,
    startingFamilyId: "A 1", accessedFamilyIds: ["A 1", "B 1"], rows: [],
    matchCount: 0, familySearchOnlyCount: 0, juuretOnlyCount: 1, hiskiOnlyCount: 0,
    familySearchCandidateCount: 0, hiskiEvidenceIds: [], conflicts: [conflict],
    warnings: [], provenance: [span])
  let proposal = CitationProposal(
    proposalId: "pilot-proposal", selectedPerson: person,
    renderedText: "Pilot citation", sourceSpans: [span], conflicts: [conflict], warnings: [])
  return FamilyResearchWorkup(
    workupId: "pilot-workup", startingFamilyId: "A 1", selectedPerson: person,
    accessedFamilyIds: ["A 1", "B 1"], parsedFamilies: [parsed], claims: [claim1, claim2],
    comparison: comparison, juuretCitationProposal: proposal, hiskiCitationProposals: [],
    hiskiEvidence: [], conflicts: [conflict], warnings: [], humanDecisionsRequired: [],
    renderedReport: "Pilot fixture")
}

private func pilotSpan(_ familyId: String) -> SourceSpan {
  SourceSpan(
    sourceId: "fixture", sourceSha256: pilotHash, familyId: familyId,
    pageReferences: ["1"], startLine: 1, endLine: 2,
    blockSha256: String(repeating: familyId == "A 1" ? "b" : "c", count: 64))
}

private let pilotHash = String(repeating: "a", count: 64)
private let pilotDate = Date(timeIntervalSince1970: 1_800_000_000)
