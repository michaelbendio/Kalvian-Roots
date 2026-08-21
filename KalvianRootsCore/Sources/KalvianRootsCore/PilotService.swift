import CryptoKit
import Foundation

public struct PilotDefinition: Codable, Equatable, Sendable {
  public let name: String
  public let familyIds: [String]
  public let traversalSessionId: String
  public let citationReviewIds: [String]

  public init(
    name: String, familyIds: [String], traversalSessionId: String,
    citationReviewIds: [String]
  ) {
    self.name = name
    self.familyIds = familyIds
    self.traversalSessionId = traversalSessionId
    self.citationReviewIds = citationReviewIds
  }
}

public enum PilotMetricStatus: String, Codable, Sendable {
  case measured
  case pendingHumanReview = "pending_human_review"
  case unavailable
}

public struct PilotMetric: Codable, Equatable, Sendable {
  public let code: String
  public let label: String
  public let status: PilotMetricStatus
  public let value: Double?
  public let unit: String?
  public let numerator: Int?
  public let denominator: Int?
  public let note: String
}

public enum PilotReadiness: String, Codable, Sendable {
  case pending
  case ready
  case notReady = "not_ready"
}

public struct PilotReadinessEvent: Codable, Equatable, Sendable {
  public let decisionId: String
  public let readiness: PilotReadiness
  public let decidedAt: String
  public let note: String
}

public struct PilotReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let pilotId: String
  public let definition: PilotDefinition
  public let sourceSHA256: String
  public let generatedAt: String
  public let metrics: [PilotMetric]
  public let completedFamilyIds: [String]
  public let incompleteFamilies: [String: String]
  public let unresolvedConflictFields: [String: Int]
  public let citationReviewIds: [String]
  public let sourceSpans: [SourceSpan]
  public let readiness: PilotReadiness
  public let readinessHistory: [PilotReadinessEvent]
  public let broaderTraversalBlocked: Bool

  public init(
    pilotId: String, definition: PilotDefinition, sourceSHA256: String,
    generatedAt: String, metrics: [PilotMetric], completedFamilyIds: [String],
    incompleteFamilies: [String: String], unresolvedConflictFields: [String: Int],
    citationReviewIds: [String], sourceSpans: [SourceSpan], readiness: PilotReadiness,
    readinessHistory: [PilotReadinessEvent]
  ) {
    schemaVersion = 1
    self.pilotId = pilotId
    self.definition = definition
    self.sourceSHA256 = sourceSHA256
    self.generatedAt = generatedAt
    self.metrics = metrics
    self.completedFamilyIds = completedFamilyIds
    self.incompleteFamilies = incompleteFamilies
    self.unresolvedConflictFields = unresolvedConflictFields
    self.citationReviewIds = citationReviewIds
    self.sourceSpans = sourceSpans
    self.readiness = readiness
    self.readinessHistory = readinessHistory
    broaderTraversalBlocked = readiness != .ready
  }
}

public enum PilotServiceError: Error, Equatable, Sendable {
  case invalidRequest(String)
  case recordNotFound(String)
  case explicitConfirmationRequired
  case storeUnavailable(String)

  public var code: String {
    switch self {
    case .invalidRequest: "invalid_request"
    case .recordNotFound: "record_not_found"
    case .explicitConfirmationRequired: "approval_required"
    case .storeUnavailable: "cache_unavailable"
    }
  }
}

extension PilotServiceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let reason): "The pilot request is invalid: \(reason)"
    case .recordNotFound(let id): "No pilot report is stored for \(id)."
    case .explicitConfirmationRequired:
      "An explicit human confirmation is required for the pilot readiness decision."
    case .storeUnavailable(let reason): "The pilot store is unavailable: \(reason)"
    }
  }
}

public protocol PilotReportStoring: Sendable {
  func report(id: String) async throws -> PilotReport?
  func save(_ report: PilotReport) async throws
}

public actor MemoryPilotReportStore: PilotReportStoring {
  private var reports: [String: PilotReport] = [:]
  public init() {}
  public func report(id: String) -> PilotReport? { reports[id] }
  public func save(_ report: PilotReport) { reports[report.pilotId] = report }
}

public actor FilePilotReportStore: PilotReportStoring {
  private struct Payload: Codable { let schemaVersion: Int; var reports: [String: PilotReport] }
  private let url: URL
  private let fileManager: FileManager
  private var loaded: Payload?

  public init(url: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.url = url ?? Self.defaultURL(fileManager: fileManager)
  }

  public func report(id: String) throws -> PilotReport? { try load().reports[id] }

  public func save(_ report: PilotReport) throws {
    var payload = try load()
    payload.reports[report.pilotId] = report
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(payload).write(to: url, options: [.atomic])
      loaded = payload
    } catch {
      throw PilotServiceError.storeUnavailable(error.localizedDescription)
    }
  }

  private func load() throws -> Payload {
    if let loaded { return loaded }
    guard fileManager.fileExists(atPath: url.path) else {
      let payload = Payload(schemaVersion: 1, reports: [:])
      loaded = payload
      return payload
    }
    do {
      let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
      guard payload.schemaVersion == 1 else {
        throw PilotServiceError.storeUnavailable("unsupported pilot report schema")
      }
      loaded = payload
      return payload
    } catch let error as PilotServiceError { throw error }
    catch { throw PilotServiceError.storeUnavailable(error.localizedDescription) }
  }

  private static func defaultURL(fileManager: FileManager) -> URL {
    guard let support = fileManager.urls(
      for: .applicationSupportDirectory, in: .userDomainMask).first
    else { fatalError("Application Support directory is unavailable") }
    return support.appendingPathComponent("Kalvian Roots", isDirectory: true)
      .appendingPathComponent("Pilot", isDirectory: true)
      .appendingPathComponent("reports-v1.json")
  }
}

public actor PilotService {
  private let traversalService: TraversalSessionService
  private let citationReviewService: CitationReviewService
  private let store: any PilotReportStoring
  private let now: @Sendable () -> Date

  public init(
    traversalService: TraversalSessionService,
    citationReviewService: CitationReviewService,
    store: any PilotReportStoring = FilePilotReportStore(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.traversalService = traversalService
    self.citationReviewService = citationReviewService
    self.store = store
    self.now = now
  }

  public func create(definition: PilotDefinition) async throws -> PilotReport {
    let normalizedFamilies = Self.unique(definition.familyIds)
    guard !definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      (1...25).contains(normalizedFamilies.count),
      !definition.traversalSessionId.isEmpty
    else { throw PilotServiceError.invalidRequest("name, family set, and traversal session are required") }
    let normalizedDefinition = PilotDefinition(
      name: definition.name, familyIds: normalizedFamilies,
      traversalSessionId: definition.traversalSessionId,
      citationReviewIds: Self.unique(definition.citationReviewIds))
    let pilotId = Self.stableID(
      normalizedDefinition.name, normalizedDefinition.familyIds.joined(separator: ","),
      normalizedDefinition.traversalSessionId,
      normalizedDefinition.citationReviewIds.joined(separator: ","))
    if let existing = try await store.report(id: pilotId) { return existing }
    return try await build(
      pilotId: pilotId, definition: normalizedDefinition, readinessHistory: [])
  }

  public func get(pilotId: String) async throws -> PilotReport {
    guard let report = try await store.report(id: pilotId) else {
      throw PilotServiceError.recordNotFound(pilotId)
    }
    return report
  }

  public func refresh(pilotId: String) async throws -> PilotReport {
    let existing = try await get(pilotId: pilotId)
    return try await build(
      pilotId: existing.pilotId, definition: existing.definition,
      readinessHistory: existing.readinessHistory)
  }

  public func recordReadiness(
    pilotId: String, readiness: PilotReadiness, note: String,
    explicitHumanConfirmation: Bool
  ) async throws -> PilotReport {
    guard explicitHumanConfirmation else {
      throw PilotServiceError.explicitConfirmationRequired
    }
    guard readiness != .pending else {
      throw PilotServiceError.invalidRequest("readiness must be ready or not_ready")
    }
    let current = try await refresh(pilotId: pilotId)
    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedNote.isEmpty else {
      throw PilotServiceError.invalidRequest("a readiness rationale is required")
    }
    let timestamp = Self.rfc3339(now())
    let event = PilotReadinessEvent(
      decisionId: Self.stableID(
        pilotId, readiness.rawValue, timestamp, String(current.readinessHistory.count)),
      readiness: readiness, decidedAt: timestamp, note: trimmedNote)
    return try await build(
      pilotId: current.pilotId, definition: current.definition,
      readinessHistory: current.readinessHistory + [event])
  }

  private func build(
    pilotId: String, definition: PilotDefinition,
    readinessHistory: [PilotReadinessEvent]
  ) async throws -> PilotReport {
    let traversal: TraversalSession
    do { traversal = try await traversalService.get(sessionId: definition.traversalSessionId) }
    catch { throw PilotServiceError.recordNotFound(definition.traversalSessionId) }
    let allowed = Set(traversal.policy.allowedFamilyIds.map(Self.key))
    guard definition.familyIds.allSatisfy({ allowed.contains(Self.key($0)) }) else {
      throw PilotServiceError.invalidRequest("every pilot family must be inside the traversal allow-list")
    }
    var reviews: [CitationReviewRecord] = []
    for reviewId in definition.citationReviewIds {
      do { reviews.append(try await citationReviewService.get(reviewId: reviewId)) }
      catch { throw PilotServiceError.recordNotFound(reviewId) }
    }
    let familySet = Set(definition.familyIds.map(Self.key))
    guard reviews.allSatisfy({ familySet.contains(Self.key($0.workup.startingFamilyId)) }) else {
      throw PilotServiceError.invalidRequest("a citation review is outside the defined pilot family set")
    }

    let completed = traversal.items.filter {
      familySet.contains(Self.key($0.familyId)) && $0.status == .completed
    }.map(\.familyId)
    var incomplete: [String: String] = [:]
    for familyId in definition.familyIds where !completed.map(Self.key).contains(Self.key(familyId)) {
      let item = traversal.items.first { Self.key($0.familyId) == Self.key(familyId) }
      incomplete[familyId] = item?.incompleteReason ?? "The family has not completed within the pilot traversal."
    }
    var conflictFields: [String: Int] = [:]
    for conflict in reviews.flatMap({ $0.workup.conflicts }) {
      conflictFields[conflict.field, default: 0] += 1
    }
    let allItems = reviews.flatMap(\.items)
    let decidedItems = allItems.filter { $0.currentDisposition != nil }
    let acceptedItems = allItems.filter { $0.currentDisposition == .approved }
    let rejectedItems = allItems.filter { $0.currentDisposition == .rejected }
    let hiskiItems = allItems.filter { $0.proposal.citationType.hasPrefix("hiski_") }
    let decidedHiski = hiskiItems.filter {
      $0.currentDisposition == .approved || $0.currentDisposition == .rejected
    }
    let acceptedHiski = hiskiItems.filter { $0.currentDisposition == .approved }
    let attachedItems = allItems.filter { $0.latestAttachmentOutcome == .attached }
    let reviewSeconds = Self.reviewSeconds(reviews)
    let networkFailures = traversal.items.filter {
      guard let code = $0.lastErrorCode else { return false }
      return code == "external_service_unavailable" || code == "rate_limited"
        || code == "network_error" || code == "ai_request_failed"
    }.count

    let metrics = [
      Self.ratioMetric(
        code: "family_completion", label: "Family completion",
        numerator: completed.count, denominator: definition.familyIds.count,
        note: "Completed within the explicit pilot family set."),
      PilotMetric(
        code: "parsing_accuracy", label: "Parsing accuracy", status: .pendingHumanReview,
        value: nil, unit: nil, numerator: nil, denominator: nil,
        note: "Requires human comparison of parsed fields with exact family blocks."),
      PilotMetric(
        code: "reference_resolution_accuracy", label: "Reference-resolution accuracy",
        status: .pendingHumanReview, value: nil, unit: nil, numerator: nil,
        denominator: nil,
        note: "Requires human confirmation that resolved people and couples are correct."),
      Self.conditionalRatioMetric(
        code: "hiski_match_quality", label: "HiSki match approval rate",
        numerator: acceptedHiski.count, denominator: decidedHiski.count,
        pendingNote: "No HiSki proposal has both an identity decision and citation disposition."),
      Self.conditionalRatioMetric(
        code: "citation_quality", label: "Citation approval rate",
        numerator: acceptedItems.count,
        denominator: acceptedItems.count + rejectedItems.count,
        pendingNote: "No citation has been approved or rejected."),
      PilotMetric(
        code: "human_review_time", label: "Recorded human review time",
        status: decidedItems.isEmpty ? .pendingHumanReview : .measured,
        value: decidedItems.isEmpty ? nil : reviewSeconds, unit: "seconds",
        numerator: nil, denominator: nil,
        note: "Elapsed time from review creation through the latest recorded decision."),
      PilotMetric(
        code: "deepseek_calls", label: "DeepSeek calls", status: .measured,
        value: Double(traversal.usage.deepSeekCalls), unit: "calls",
        numerator: traversal.usage.deepSeekCalls, denominator: nil,
        note: "Actual calls recorded by the bounded traversal."),
      PilotMetric(
        code: "ai_cost", label: "AI cost", status: .unavailable,
        value: nil, unit: "USD", numerator: nil, denominator: nil,
        note: "Token usage and provider pricing are not retained; call count is reported separately."),
      PilotMetric(
        code: "network_failures", label: "Network failures", status: .measured,
        value: Double(networkFailures), unit: "failures", numerator: networkFailures,
        denominator: nil, note: "Retryable DeepSeek or HiSki network failures in pilot work items."),
      PilotMetric(
        code: "unresolved_conflicts", label: "Unresolved genealogical conflicts",
        status: .measured, value: Double(conflictFields.values.reduce(0, +)),
        unit: "conflicts", numerator: conflictFields.values.reduce(0, +),
        denominator: nil, note: "Grouped by source field in unresolvedConflictFields."),
      PilotMetric(
        code: "attached_citations", label: "Confirmed attached citations",
        status: .measured, value: Double(attachedItems.count), unit: "citations",
        numerator: attachedItems.count, denominator: allItems.count,
        note: "Only explicit human-reported visible-UI attachment outcomes are counted."),
    ]
    let readiness = readinessHistory.last?.readiness ?? .pending
    var seenSpans: Set<String> = []
    let sourceSpans = (
      traversal.items.compactMap(\.sourceSpan)
        + reviews.flatMap { $0.items.flatMap { $0.proposal.sourceSpans } }
    ).filter { seenSpans.insert("\($0.sourceSha256)|\($0.blockSha256)").inserted }
    let report = PilotReport(
      pilotId: pilotId, definition: definition, sourceSHA256: traversal.sourceSHA256,
      generatedAt: Self.rfc3339(now()), metrics: metrics,
      completedFamilyIds: completed, incompleteFamilies: incomplete,
      unresolvedConflictFields: conflictFields,
      citationReviewIds: reviews.map(\.reviewId), sourceSpans: sourceSpans,
      readiness: readiness,
      readinessHistory: readinessHistory)
    try await store.save(report)
    return report
  }

  private static func ratioMetric(
    code: String, label: String, numerator: Int, denominator: Int, note: String
  ) -> PilotMetric {
    PilotMetric(
      code: code, label: label, status: .measured,
      value: denominator == 0 ? 0 : Double(numerator) / Double(denominator), unit: "ratio",
      numerator: numerator, denominator: denominator, note: note)
  }

  private static func conditionalRatioMetric(
    code: String, label: String, numerator: Int, denominator: Int, pendingNote: String
  ) -> PilotMetric {
    guard denominator > 0 else {
      return PilotMetric(
        code: code, label: label, status: .pendingHumanReview, value: nil, unit: "ratio",
        numerator: numerator, denominator: denominator, note: pendingNote)
    }
    return ratioMetric(
      code: code, label: label, numerator: numerator, denominator: denominator,
      note: "Based only on individually recorded human dispositions.")
  }

  private static func reviewSeconds(_ reviews: [CitationReviewRecord]) -> Double {
    reviews.reduce(0) { total, review in
      guard review.items.contains(where: { !$0.decisions.isEmpty }),
        let start = date(review.createdAt), let end = date(review.updatedAt)
      else { return total }
      return total + max(0, end.timeIntervalSince(start))
    }
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.compactMap {
      let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(key(trimmed)).inserted else { return nil }
      return trimmed
    }
  }

  private static func key(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: \Character.isWhitespace).joined(separator: " ").uppercased()
  }

  private static func rfc3339(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
  }

  private static func stableID(_ parts: String...) -> String {
    SHA256.hash(data: Data(parts.joined(separator: "|").utf8)).map {
      String(format: "%02x", $0)
    }.joined()
  }
}
