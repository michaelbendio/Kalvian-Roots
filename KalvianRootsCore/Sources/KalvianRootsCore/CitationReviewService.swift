import CryptoKit
import Foundation

public enum CitationDisposition: String, Codable, Sendable {
  case approved
  case rejected
  case deferred
}

public enum AttachmentOutcomeStatus: String, Codable, Sendable {
  case copied
  case attached
  case failed
  case deferred
}

public struct CitationDecisionEvent: Codable, Equatable, Sendable {
  public let decisionId: String
  public let proposalId: String
  public let disposition: CitationDisposition
  public let decidedAt: String
  public let note: String?
}

public struct AttachmentOutcomeEvent: Codable, Equatable, Sendable {
  public let outcomeId: String
  public let proposalId: String
  public let status: AttachmentOutcomeStatus
  public let recordedAt: String
  public let familySearchPersonId: String?
  public let note: String?
}

public struct CitationReviewItem: Codable, Equatable, Sendable {
  public let proposal: CitationProposal
  public let decisions: [CitationDecisionEvent]
  public let attachmentOutcomes: [AttachmentOutcomeEvent]

  public var currentDisposition: CitationDisposition? { decisions.last?.disposition }
  public var latestAttachmentOutcome: AttachmentOutcomeStatus? { attachmentOutcomes.last?.status }
}

public struct CitationReviewRecord: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let reviewId: String
  public let workup: FamilyResearchWorkup
  public let attachmentMode: String
  public let createdAt: String
  public let updatedAt: String
  public let items: [CitationReviewItem]

  public init(
    reviewId: String, workup: FamilyResearchWorkup,
    attachmentMode: String = "manual_or_visible_ui_only", createdAt: String,
    updatedAt: String, items: [CitationReviewItem]
  ) {
    schemaVersion = 1
    self.reviewId = reviewId
    self.workup = workup
    self.attachmentMode = attachmentMode
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.items = items
  }
}

public enum CitationReviewError: Error, Equatable, Sendable {
  case recordNotFound(String)
  case proposalNotFound(String)
  case explicitConfirmationRequired
  case proposalNotApproved(String)
  case invalidRequest(String)
  case storeUnavailable(String)

  public var code: String {
    switch self {
    case .recordNotFound, .proposalNotFound: "record_not_found"
    case .explicitConfirmationRequired, .proposalNotApproved: "approval_required"
    case .invalidRequest: "invalid_request"
    case .storeUnavailable: "cache_unavailable"
    }
  }
}

extension CitationReviewError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .recordNotFound(let id): "No citation review is stored for \(id)."
    case .proposalNotFound(let id): "Citation proposal \(id) is not part of this review."
    case .explicitConfirmationRequired:
      "An explicit human confirmation is required to record this decision."
    case .proposalNotApproved(let id):
      "Citation proposal \(id) must be individually approved before an attachment outcome is recorded."
    case .invalidRequest(let reason): "The citation review request is invalid: \(reason)"
    case .storeUnavailable(let reason): "The citation review store is unavailable: \(reason)"
    }
  }
}

public protocol CitationReviewStoring: Sendable {
  func review(id: String) async throws -> CitationReviewRecord?
  func save(_ review: CitationReviewRecord) async throws
}

public actor MemoryCitationReviewStore: CitationReviewStoring {
  private var reviews: [String: CitationReviewRecord] = [:]
  public init() {}
  public func review(id: String) -> CitationReviewRecord? { reviews[id] }
  public func save(_ review: CitationReviewRecord) { reviews[review.reviewId] = review }
}

public actor FileCitationReviewStore: CitationReviewStoring {
  private struct Payload: Codable {
    let schemaVersion: Int
    var reviews: [String: CitationReviewRecord]
  }

  private let url: URL
  private let fileManager: FileManager

  public init(url: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.url = url ?? Self.defaultURL(fileManager: fileManager)
  }

  public func review(id: String) throws -> CitationReviewRecord? { try load().reviews[id] }

  public func save(_ review: CitationReviewRecord) throws {
    var payload = try load()
    payload.reviews[review.reviewId] = review
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(payload).write(to: url, options: [.atomic])
    } catch {
      throw CitationReviewError.storeUnavailable(error.localizedDescription)
    }
  }

  private func load() throws -> Payload {
    guard fileManager.fileExists(atPath: url.path) else {
      let payload = Payload(schemaVersion: 1, reviews: [:])
      return payload
    }
    do {
      let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
      guard payload.schemaVersion == 1 else {
        throw CitationReviewError.storeUnavailable("unsupported citation review schema")
      }
      return payload
    } catch let error as CitationReviewError { throw error }
    catch { throw CitationReviewError.storeUnavailable(error.localizedDescription) }
  }

  private static func defaultURL(fileManager: FileManager) -> URL {
    guard let support = fileManager.urls(
      for: .applicationSupportDirectory, in: .userDomainMask).first
    else { fatalError("Application Support directory is unavailable") }
    return support.appendingPathComponent("Kalvian Roots", isDirectory: true)
      .appendingPathComponent("Research", isDirectory: true)
      .appendingPathComponent("citation-reviews-v1.json")
  }
}

public actor CitationReviewService {
  private let store: any CitationReviewStoring
  private let now: @Sendable () -> Date

  public init(
    store: any CitationReviewStoring = FileCitationReviewStore(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.now = now
  }

  public func prepare(workup: FamilyResearchWorkup) async throws -> CitationReviewRecord {
    if let existing = try await store.review(id: workup.workupId) {
      guard existing.workup == workup else {
        throw CitationReviewError.invalidRequest(
          "the workup identifier is already associated with different evidence")
      }
      return existing
    }
    let timestamp = Self.rfc3339(now())
    let proposals = [workup.juuretCitationProposal] + workup.hiskiCitationProposals
    let review = CitationReviewRecord(
      reviewId: workup.workupId, workup: workup, createdAt: timestamp,
      updatedAt: timestamp,
      items: proposals.map {
        CitationReviewItem(proposal: $0, decisions: [], attachmentOutcomes: [])
      })
    try await store.save(review)
    return review
  }

  public func get(reviewId: String) async throws -> CitationReviewRecord {
    guard let review = try await store.review(id: reviewId) else {
      throw CitationReviewError.recordNotFound(reviewId)
    }
    return review
  }

  public func recordDecision(
    reviewId: String, proposalId: String, disposition: CitationDisposition,
    note: String?, explicitHumanConfirmation: Bool
  ) async throws -> CitationReviewRecord {
    guard explicitHumanConfirmation else {
      throw CitationReviewError.explicitConfirmationRequired
    }
    let review = try await get(reviewId: reviewId)
    guard let index = review.items.firstIndex(where: { $0.proposal.proposalId == proposalId }) else {
      throw CitationReviewError.proposalNotFound(proposalId)
    }
    let timestamp = Self.rfc3339(now())
    let prior = review.items[index]
    let event = CitationDecisionEvent(
      decisionId: Self.stableID(
        reviewId, proposalId, disposition.rawValue, timestamp, String(prior.decisions.count)),
      proposalId: proposalId, disposition: disposition, decidedAt: timestamp,
      note: Self.nonempty(note))
    var items = review.items
    items[index] = CitationReviewItem(
      proposal: prior.proposal, decisions: prior.decisions + [event],
      attachmentOutcomes: prior.attachmentOutcomes)
    let updated = CitationReviewRecord(
      reviewId: review.reviewId, workup: review.workup,
      attachmentMode: review.attachmentMode, createdAt: review.createdAt,
      updatedAt: timestamp, items: items)
    try await store.save(updated)
    return updated
  }

  public func recordAttachmentOutcome(
    reviewId: String, proposalId: String, status: AttachmentOutcomeStatus,
    familySearchPersonId: String?, note: String?, explicitHumanConfirmation: Bool
  ) async throws -> CitationReviewRecord {
    guard explicitHumanConfirmation else {
      throw CitationReviewError.explicitConfirmationRequired
    }
    let review = try await get(reviewId: reviewId)
    guard let index = review.items.firstIndex(where: { $0.proposal.proposalId == proposalId }) else {
      throw CitationReviewError.proposalNotFound(proposalId)
    }
    let prior = review.items[index]
    guard prior.currentDisposition == .approved else {
      throw CitationReviewError.proposalNotApproved(proposalId)
    }
    let personId = Self.nonempty(familySearchPersonId)
    if status == .attached && personId == nil {
      throw CitationReviewError.invalidRequest(
        "familySearchPersonId is required when status is attached")
    }
    let timestamp = Self.rfc3339(now())
    let event = AttachmentOutcomeEvent(
      outcomeId: Self.stableID(
        reviewId, proposalId, status.rawValue, timestamp,
        String(prior.attachmentOutcomes.count)),
      proposalId: proposalId, status: status, recordedAt: timestamp,
      familySearchPersonId: personId, note: Self.nonempty(note))
    var items = review.items
    items[index] = CitationReviewItem(
      proposal: prior.proposal, decisions: prior.decisions,
      attachmentOutcomes: prior.attachmentOutcomes + [event])
    let updated = CitationReviewRecord(
      reviewId: review.reviewId, workup: review.workup,
      attachmentMode: review.attachmentMode, createdAt: review.createdAt,
      updatedAt: timestamp, items: items)
    try await store.save(updated)
    return updated
  }

  private static func nonempty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty else { return nil }
    return trimmed
  }

  private static func rfc3339(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func stableID(_ parts: String...) -> String {
    SHA256.hash(data: Data(parts.joined(separator: "|").utf8)).map {
      String(format: "%02x", $0)
    }.joined()
  }
}
