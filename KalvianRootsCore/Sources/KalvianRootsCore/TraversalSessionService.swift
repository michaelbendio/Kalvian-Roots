import CryptoKit
import Foundation

public struct TraversalPolicy: Codable, Equatable, Sendable {
  public let maxFamilies: Int
  public let maxDepth: Int
  public let maxAttemptsPerFamily: Int
  public let maxItemsPerResume: Int
  public let maxDeepSeekCalls: Int
  public let maxHiskiCalls: Int
  public let minimumSecondsBetweenItems: Int
  public let allowedFamilyIds: [String]

  public init(
    maxFamilies: Int, maxDepth: Int, maxAttemptsPerFamily: Int = 2,
    maxItemsPerResume: Int = 1, maxDeepSeekCalls: Int = 0, maxHiskiCalls: Int = 0,
    minimumSecondsBetweenItems: Int = 0, allowedFamilyIds: [String]
  ) {
    self.maxFamilies = maxFamilies
    self.maxDepth = maxDepth
    self.maxAttemptsPerFamily = maxAttemptsPerFamily
    self.maxItemsPerResume = maxItemsPerResume
    self.maxDeepSeekCalls = maxDeepSeekCalls
    self.maxHiskiCalls = maxHiskiCalls
    self.minimumSecondsBetweenItems = minimumSecondsBetweenItems
    self.allowedFamilyIds = allowedFamilyIds
  }

  public var isValid: Bool {
    (1...25).contains(maxFamilies) && (0...10).contains(maxDepth)
      && (1...5).contains(maxAttemptsPerFamily) && (1...10).contains(maxItemsPerResume)
      && (0...25).contains(maxDeepSeekCalls) && (0...100).contains(maxHiskiCalls)
      && (0...300).contains(minimumSecondsBetweenItems)
      && (1...25).contains(allowedFamilyIds.count)
  }
}

public enum TraversalItemStatus: String, Codable, Sendable {
  case queued
  case inProgress = "in_progress"
  case retryPending = "retry_pending"
  case completed
  case failed
}

public struct TraversalWorkItem: Codable, Equatable, Sendable {
  public let familyId: String
  public let depth: Int
  public let discoveredFrom: String?
  public var status: TraversalItemStatus
  public var attempts: Int
  public var sourceSpan: SourceSpan?
  public var referencedFamilyIds: [String]
  public var lastErrorCode: String?
  public var incompleteReason: String?
  public var auditRefs: [String]
  public var completedAt: String?
}

public struct TraversalUsage: Codable, Equatable, Sendable {
  public var deepSeekCalls: Int
  public var hiskiCalls: Int

  public init(deepSeekCalls: Int = 0, hiskiCalls: Int = 0) {
    self.deepSeekCalls = deepSeekCalls
    self.hiskiCalls = hiskiCalls
  }
}

public enum TraversalSessionStatus: String, Codable, Sendable {
  case running
  case completed
  case incomplete
}

public struct TraversalSession: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let sessionId: String
  public let sourceSHA256: String
  public let startingFamilyIds: [String]
  public let policy: TraversalPolicy
  public var items: [TraversalWorkItem]
  public var usage: TraversalUsage
  public var status: TraversalSessionStatus
  public var stopReason: String?
  public let createdAt: String
  public var updatedAt: String

  public var completedFamilyIds: [String] {
    items.filter { $0.status == .completed }.map(\.familyId)
  }
}

public struct TraversalBudget: Equatable, Sendable {
  public let remainingDeepSeekCalls: Int
  public let remainingHiskiCalls: Int
}

public struct TraversalWorkResult: Equatable, Sendable {
  public let sourceSpan: SourceSpan
  public let referencedFamilyIds: [String]
  public let deepSeekCalls: Int
  public let hiskiCalls: Int
  public let auditRefs: [String]

  public init(
    sourceSpan: SourceSpan, referencedFamilyIds: [String], deepSeekCalls: Int = 0,
    hiskiCalls: Int = 0, auditRefs: [String] = []
  ) {
    self.sourceSpan = sourceSpan
    self.referencedFamilyIds = referencedFamilyIds
    self.deepSeekCalls = deepSeekCalls
    self.hiskiCalls = hiskiCalls
    self.auditRefs = auditRefs
  }
}

public struct TraversalWorkFailure: Error, Equatable, Sendable {
  public let code: String
  public let message: String
  public let retryable: Bool

  public init(code: String, message: String, retryable: Bool) {
    self.code = code
    self.message = message
    self.retryable = retryable
  }
}

public enum TraversalSessionError: Error, Equatable, Sendable {
  case invalidRequest(String)
  case recordNotFound(String)
  case storeUnavailable(String)

  public var code: String {
    switch self {
    case .invalidRequest: "invalid_request"
    case .recordNotFound: "record_not_found"
    case .storeUnavailable: "cache_unavailable"
    }
  }
}

extension TraversalSessionError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let reason): "The traversal request is invalid: \(reason)"
    case .recordNotFound(let id): "No traversal session is stored for \(id)."
    case .storeUnavailable(let reason): "The traversal checkpoint store is unavailable: \(reason)"
    }
  }
}

public protocol TraversalWorkProcessing: Sendable {
  func process(
    familyId: String, sourceSHA256: String, budget: TraversalBudget
  ) async throws -> TraversalWorkResult
}

public protocol TraversalSessionStoring: Sendable {
  func session(id: String) async throws -> TraversalSession?
  func save(_ session: TraversalSession) async throws
}

public actor MemoryTraversalSessionStore: TraversalSessionStoring {
  private var sessions: [String: TraversalSession] = [:]
  public init() {}
  public func session(id: String) -> TraversalSession? { sessions[id] }
  public func save(_ session: TraversalSession) { sessions[session.sessionId] = session }
}

public actor FileTraversalSessionStore: TraversalSessionStoring {
  private struct Payload: Codable { let schemaVersion: Int; var sessions: [String: TraversalSession] }
  private let url: URL
  private let fileManager: FileManager
  private var loaded: Payload?

  public init(url: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.url = url ?? Self.defaultURL(fileManager: fileManager)
  }

  public func session(id: String) throws -> TraversalSession? { try load().sessions[id] }

  public func save(_ session: TraversalSession) throws {
    var payload = try load()
    payload.sessions[session.sessionId] = session
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(payload).write(to: url, options: [.atomic])
      loaded = payload
    } catch {
      throw TraversalSessionError.storeUnavailable(error.localizedDescription)
    }
  }

  private func load() throws -> Payload {
    if let loaded { return loaded }
    guard fileManager.fileExists(atPath: url.path) else {
      let payload = Payload(schemaVersion: 1, sessions: [:])
      loaded = payload
      return payload
    }
    do {
      let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
      guard payload.schemaVersion == 1 else {
        throw TraversalSessionError.storeUnavailable("unsupported traversal schema")
      }
      loaded = payload
      return payload
    } catch let error as TraversalSessionError { throw error }
    catch { throw TraversalSessionError.storeUnavailable(error.localizedDescription) }
  }

  private static func defaultURL(fileManager: FileManager) -> URL {
    guard let support = fileManager.urls(
      for: .applicationSupportDirectory, in: .userDomainMask).first
    else { fatalError("Application Support directory is unavailable") }
    return support.appendingPathComponent("Kalvian Roots", isDirectory: true)
      .appendingPathComponent("Traversal", isDirectory: true)
      .appendingPathComponent("sessions-v1.json")
  }
}

public struct ParsedFamilyTraversalWorker: TraversalWorkProcessing, Sendable {
  private let bookTextService: any BookTextServing
  private let parsingService: any FamilyParsingServing

  public init(
    bookTextService: any BookTextServing, parsingService: any FamilyParsingServing
  ) {
    self.bookTextService = bookTextService
    self.parsingService = parsingService
  }

  public func process(
    familyId: String, sourceSHA256: String, budget: TraversalBudget
  ) async throws -> TraversalWorkResult {
    do {
      let source = try await bookTextService.getFamilyText(
        familyId: familyId, expectedSourceSHA256: sourceSHA256)
      let record: ParsedFamilyRecord
      let usedDeepSeek: Bool
      do {
        // cacheOnly also imports a usable accumulated schema-2 cache entry without AI.
        record = try await parsingService.parseFamily(source: source, cachePolicy: .cacheOnly)
        usedDeepSeek = false
      } catch FamilyParsingError.cacheMiss {
        guard budget.remainingDeepSeekCalls > 0 else {
          throw TraversalWorkFailure(
            code: "deepseek_budget_exhausted",
            message: "No validated cached parse is available and the DeepSeek budget is exhausted.",
            retryable: false)
        }
        record = try await parsingService.parseFamily(source: source, cachePolicy: .useValidated)
        usedDeepSeek = record.parserImplementationVersion != "legacy-schema2-unknown"
      }
      return TraversalWorkResult(
        sourceSpan: record.span,
        referencedFamilyIds: Self.references(in: record.parsedFamily),
        deepSeekCalls: usedDeepSeek ? 1 : 0)
    } catch let failure as TraversalWorkFailure { throw failure }
    catch let error as BookTextError {
      throw TraversalWorkFailure(code: error.code, message: error.localizedDescription, retryable: false)
    } catch let error as FamilyParsingError {
      let retryable: Bool
      switch error {
      case .aiRequestFailed: retryable = true
      default: retryable = false
      }
      throw TraversalWorkFailure(code: error.code, message: error.localizedDescription, retryable: retryable)
    } catch {
      throw TraversalWorkFailure(
        code: "internal_error", message: error.localizedDescription, retryable: true)
    }
  }

  private static func references(in family: Family) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for couple in family.couples {
      for person in [couple.husband, couple.wife] + couple.children {
        for value in [person.asChild, person.asParent, person.spouseParentsFamilyId] {
          guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
          else { continue }
          let key = normalize(value)
          if seen.insert(key).inserted { result.append(value) }
        }
      }
    }
    return result
  }
}

public actor TraversalSessionService {
  private let worker: any TraversalWorkProcessing
  private let store: any TraversalSessionStoring
  private let now: @Sendable () -> Date

  public init(
    worker: any TraversalWorkProcessing, store: any TraversalSessionStoring = FileTraversalSessionStore(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.worker = worker
    self.store = store
    self.now = now
  }

  public func start(
    startingFamilyIds: [String], sourceSHA256: String, policy: TraversalPolicy
  ) async throws -> TraversalSession {
    guard policy.isValid else { throw TraversalSessionError.invalidRequest("policy is out of bounds") }
    let starts = unique(startingFamilyIds)
    let allowed = Set(policy.allowedFamilyIds.map(normalize))
    guard !starts.isEmpty, starts.allSatisfy({ allowed.contains(normalize($0)) }) else {
      throw TraversalSessionError.invalidRequest("starting families must be inside allowedFamilyIds")
    }
    guard starts.count <= policy.maxFamilies else {
      throw TraversalSessionError.invalidRequest("starting families exceed maxFamilies")
    }
    let id = stableID(sourceSHA256: sourceSHA256, starts: starts, policy: policy)
    if let existing = try await store.session(id: id) { return existing }
    let timestamp = rfc3339(now())
    let items = starts.map {
      TraversalWorkItem(
        familyId: $0, depth: 0, discoveredFrom: nil, status: .queued, attempts: 0,
        sourceSpan: nil, referencedFamilyIds: [], lastErrorCode: nil,
        incompleteReason: nil, auditRefs: [], completedAt: nil)
    }
    let session = TraversalSession(
      schemaVersion: 1, sessionId: id, sourceSHA256: sourceSHA256,
      startingFamilyIds: starts, policy: policy, items: items, usage: TraversalUsage(),
      status: .running, stopReason: nil, createdAt: timestamp, updatedAt: timestamp)
    try await store.save(session)
    return session
  }

  public func get(sessionId: String) async throws -> TraversalSession {
    guard let session = try await store.session(id: sessionId) else {
      throw TraversalSessionError.recordNotFound(sessionId)
    }
    return session
  }

  public func resume(sessionId: String) async throws -> TraversalSession {
    var session = try await get(sessionId: sessionId)
    guard session.status != .completed else { return session }
    recoverInterruptedItems(in: &session)
    session.stopReason = nil
    let batchLimit = session.policy.maxItemsPerResume
    var attempted = 0

    while attempted < batchLimit,
      let index = session.items.firstIndex(where: {
        $0.status == .queued || $0.status == .retryPending
      })
    {
      if rateLimited(session) {
        session.stopReason = "minimum_interval"
        break
      }
      session.items[index].status = .inProgress
      session.items[index].attempts += 1
      session.updatedAt = rfc3339(now())
      try await store.save(session)
      attempted += 1

      let budget = TraversalBudget(
        remainingDeepSeekCalls: max(0, session.policy.maxDeepSeekCalls - session.usage.deepSeekCalls),
        remainingHiskiCalls: max(0, session.policy.maxHiskiCalls - session.usage.hiskiCalls))
      do {
        let result = try await worker.process(
          familyId: session.items[index].familyId,
          sourceSHA256: session.sourceSHA256, budget: budget)
        guard result.deepSeekCalls <= budget.remainingDeepSeekCalls,
          result.hiskiCalls <= budget.remainingHiskiCalls
        else {
          throw TraversalWorkFailure(
            code: "resource_limit_exceeded",
            message: "A worker exceeded the traversal external-call budget.", retryable: false)
        }
        session.usage.deepSeekCalls += result.deepSeekCalls
        session.usage.hiskiCalls += result.hiskiCalls
        session.items[index].sourceSpan = result.sourceSpan
        session.items[index].referencedFamilyIds = unique(result.referencedFamilyIds)
        session.items[index].auditRefs = result.auditRefs
        session.items[index].status = .completed
        session.items[index].lastErrorCode = nil
        session.items[index].incompleteReason = nil
        session.items[index].completedAt = rfc3339(now())
        enqueueReferences(from: index, in: &session)
      } catch let failure as TraversalWorkFailure {
        session.items[index].lastErrorCode = failure.code
        session.items[index].incompleteReason = failure.message
        session.items[index].status =
          failure.retryable && session.items[index].attempts < session.policy.maxAttemptsPerFamily
          ? .retryPending : .failed
      } catch {
        session.items[index].lastErrorCode = "internal_error"
        session.items[index].incompleteReason = error.localizedDescription
        session.items[index].status =
          session.items[index].attempts < session.policy.maxAttemptsPerFamily
          ? .retryPending : .failed
      }
      session.updatedAt = rfc3339(now())
      try await store.save(session)
    }

    finalize(&session, hitBatchLimit: attempted == batchLimit)
    try await store.save(session)
    return session
  }

  private func recoverInterruptedItems(in session: inout TraversalSession) {
    for index in session.items.indices where session.items[index].status == .inProgress {
      session.items[index].lastErrorCode = "interrupted"
      session.items[index].incompleteReason = "The prior run ended before this family was checkpointed."
      session.items[index].status =
        session.items[index].attempts < session.policy.maxAttemptsPerFamily
        ? .retryPending : .failed
    }
  }

  private func enqueueReferences(from index: Int, in session: inout TraversalSession) {
    let item = session.items[index]
    guard item.depth < session.policy.maxDepth else { return }
    let allowed = Set(session.policy.allowedFamilyIds.map(normalize))
    var known = Set(session.items.map { normalize($0.familyId) })
    for reference in item.referencedFamilyIds {
      let key = normalize(reference)
      guard allowed.contains(key), !known.contains(key), session.items.count < session.policy.maxFamilies
      else { continue }
      known.insert(key)
      session.items.append(TraversalWorkItem(
        familyId: reference, depth: item.depth + 1, discoveredFrom: item.familyId,
        status: .queued, attempts: 0, sourceSpan: nil, referencedFamilyIds: [],
        lastErrorCode: nil, incompleteReason: nil, auditRefs: [], completedAt: nil))
    }
  }

  private func rateLimited(_ session: TraversalSession) -> Bool {
    guard session.policy.minimumSecondsBetweenItems > 0,
      let latest = session.items.compactMap(\.completedAt).compactMap(Self.date).max()
    else { return false }
    return now().timeIntervalSince(latest) < Double(session.policy.minimumSecondsBetweenItems)
  }

  private func finalize(_ session: inout TraversalSession, hitBatchLimit: Bool) {
    let hasPending = session.items.contains { $0.status == .queued || $0.status == .retryPending }
    let hasFailure = session.items.contains { $0.status == .failed }
    if hasPending {
      session.status = .running
      if session.stopReason == nil && hitBatchLimit { session.stopReason = "batch_limit" }
    } else if hasFailure {
      session.status = .incomplete
      session.stopReason = "families_failed"
    } else {
      session.status = .completed
      session.stopReason = nil
    }
    session.updatedAt = rfc3339(now())
  }

  private func stableID(
    sourceSHA256: String, starts: [String], policy: TraversalPolicy
  ) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let policyData = (try? encoder.encode(policy)) ?? Data()
    let material = sourceSHA256 + "|" + starts.map(normalize).joined(separator: ",")
      + "|" + String(decoding: policyData, as: UTF8.self)
    return "traversal-" + SHA256.hash(data: Data(material.utf8)).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private func rfc3339(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
  }
}

private func normalize(_ value: String) -> String {
  value.trimmingCharacters(in: .whitespacesAndNewlines)
    .split(whereSeparator: \Character.isWhitespace).joined(separator: " ").uppercased()
}

private func unique(_ values: [String]) -> [String] {
  var seen: Set<String> = []
  return values.compactMap { value in
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, seen.insert(normalize(trimmed)).inserted else { return nil }
    return trimmed
  }
}
