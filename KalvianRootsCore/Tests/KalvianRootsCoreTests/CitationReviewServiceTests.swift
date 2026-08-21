import Foundation
import Testing
@testable import KalvianRootsCore

@Suite("Citation review service")
struct CitationReviewServiceTests {
  @Test("each proposal retains an independent approved rejected or deferred history")
  func individualDecisionsAreRetained() async throws {
    let clock = ReviewClock()
    let service = CitationReviewService(
      store: MemoryCitationReviewStore(), now: { clock.next() })
    let workup = makeReviewWorkup()
    var review = try await service.prepare(workup: workup)
    #expect(review.items.count == 2)
    #expect(review.items.allSatisfy { $0.currentDisposition == nil })

    review = try await service.recordDecision(
      reviewId: review.reviewId, proposalId: review.items[0].proposal.proposalId,
      disposition: .approved, note: "Reviewed against the displayed family.",
      explicitHumanConfirmation: true)
    review = try await service.recordDecision(
      reviewId: review.reviewId, proposalId: review.items[1].proposal.proposalId,
      disposition: .deferred, note: "HiSki identity needs another check.",
      explicitHumanConfirmation: true)

    #expect(review.items[0].currentDisposition == .approved)
    #expect(review.items[1].currentDisposition == .deferred)
    #expect(review.items[0].proposal.renderedText == workup.juuretCitationProposal.renderedText)
    #expect(review.items[1].proposal.sourceURL == "https://hiski.example/record")
  }

  @Test("decisions and attachment outcomes require explicit human confirmation")
  func explicitConfirmationIsRequired() async throws {
    let service = CitationReviewService(store: MemoryCitationReviewStore())
    let review = try await service.prepare(workup: makeReviewWorkup())
    let proposalId = review.items[0].proposal.proposalId

    await #expect(throws: CitationReviewError.explicitConfirmationRequired) {
      try await service.recordDecision(
        reviewId: review.reviewId, proposalId: proposalId, disposition: .approved,
        note: nil, explicitHumanConfirmation: false)
    }
    await #expect(throws: CitationReviewError.proposalNotApproved(proposalId)) {
      try await service.recordAttachmentOutcome(
        reviewId: review.reviewId, proposalId: proposalId, status: .copied,
        familySearchPersonId: nil, note: nil, explicitHumanConfirmation: true)
    }
  }

  @Test("a supervised attachment remains traceable to proposal workup person and sources")
  func attachmentTraceability() async throws {
    let service = CitationReviewService(store: MemoryCitationReviewStore())
    var review = try await service.prepare(workup: makeReviewWorkup())
    let proposalId = review.items[0].proposal.proposalId
    review = try await service.recordDecision(
      reviewId: review.reviewId, proposalId: proposalId, disposition: .approved,
      note: nil, explicitHumanConfirmation: true)
    review = try await service.recordAttachmentOutcome(
      reviewId: review.reviewId, proposalId: proposalId, status: .attached,
      familySearchPersonId: "KN1X-VHG", note: "Attached through visible FamilySearch UI.",
      explicitHumanConfirmation: true)

    let outcome = try #require(review.items[0].attachmentOutcomes.last)
    #expect(outcome.familySearchPersonId == "KN1X-VHG")
    #expect(review.workup.selectedPerson.familySearchId == "KN1X-VHG")
    #expect(review.items[0].proposal.sourceSpans == review.workup.comparison.provenance)
    #expect(review.attachmentMode == "manual_or_visible_ui_only")
  }

  @Test("file review records survive a new service instance")
  func fileStoreIsDurable() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("citation-reviews-v1.json")
    let first = CitationReviewService(store: FileCitationReviewStore(url: url))
    var saved = try await first.prepare(workup: makeReviewWorkup())
    saved = try await first.recordDecision(
      reviewId: saved.reviewId, proposalId: saved.items[0].proposal.proposalId,
      disposition: .approved, note: "Durability check", explicitHumanConfirmation: true)

    let second = CitationReviewService(store: FileCitationReviewStore(url: url))
    let restored = try await second.get(reviewId: saved.reviewId)
    #expect(restored == saved)
    #expect(restored.items[0].currentDisposition == .approved)
  }
}

private final class ReviewClock: @unchecked Sendable {
  private var tick: TimeInterval = 1_800_000_000
  private let lock = NSLock()
  func next() -> Date {
    lock.lock()
    defer { lock.unlock() }
    tick += 1
    return Date(timeIntervalSince1970: tick)
  }
}

private func makeReviewWorkup() -> FamilyResearchWorkup {
  let hash = String(repeating: "a", count: 64)
  let source = SourceRevision(
    sourceId: "fixture", fileName: canonicalRootsFileName, sha256: hash,
    byteCount: 100, loadedAt: "2027-01-15T08:00:00.000Z", canonicalMarkerValid: true)
  let span = SourceSpan(
    sourceId: "fixture", sourceSha256: hash, familyId: "SAKERI 4",
    pageReferences: ["265", "266"], startLine: 1, endLine: 10,
    blockSha256: String(repeating: "b", count: 64))
  let person = PersonReference(
    familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
    rawName: "Maria", rawBirthDate: "03.03.1756", familySearchId: "KN1X-VHG")
  let family = Family(
    familyId: "SAKERI 4", pageReferences: ["265", "266"],
    husband: Person(name: "Antti"), wife: Person(name: "Brita"),
    children: [Person(name: "Maria", birthDate: "03.03.1756")])
  let parsed = ParsedFamilyRecord(
    familyId: family.familyId, source: source, span: span,
    parserImplementationVersion: "fixture", parsedFamily: family)
  let comparison = FamilyComparisonRecord(
    comparisonId: "comparison-1", contextId: "context-1", selectedPerson: person,
    startingFamilyId: family.familyId, accessedFamilyIds: [family.familyId], rows: [],
    matchCount: 0, familySearchOnlyCount: 0, juuretOnlyCount: 0, hiskiOnlyCount: 0,
    familySearchCandidateCount: 1, hiskiEvidenceIds: [], conflicts: [], warnings: [],
    provenance: [span])
  let juuret = CitationProposal(
    proposalId: "juuret-1", selectedPerson: person, renderedText: "Juuret citation",
    sourceSpans: [span], conflicts: [], warnings: [])
  let hiski = CitationProposal(
    proposalId: "hiski-1", citationType: "hiski_birth", selectedPerson: person,
    renderedText: "HiSki citation", sourceSpans: [span], conflicts: [], warnings: [],
    sourceURL: "https://hiski.example/record")
  return FamilyResearchWorkup(
    workupId: "workup-1", startingFamilyId: family.familyId, selectedPerson: person,
    accessedFamilyIds: [family.familyId], parsedFamilies: [parsed], claims: [],
    comparison: comparison, juuretCitationProposal: juuret,
    hiskiCitationProposals: [hiski], hiskiEvidence: [], conflicts: [], warnings: [],
    humanDecisionsRequired: [], renderedReport: "Fixture workup")
}
