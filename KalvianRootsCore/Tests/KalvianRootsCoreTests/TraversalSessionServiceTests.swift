import Foundation
import Testing
@testable import KalvianRootsCore

private actor StubTraversalWorker: TraversalWorkProcessing {
  enum Response: Sendable {
    case success([String], deepSeek: Int = 0, hiski: Int = 0)
    case failure(TraversalWorkFailure)
  }

  private var responses: [String: [Response]]
  private(set) var calls: [String] = []

  init(_ responses: [String: [Response]]) { self.responses = responses }

  func process(
    familyId: String, sourceSHA256: String, budget: TraversalBudget
  ) throws -> TraversalWorkResult {
    calls.append(familyId)
    let key = familyId.uppercased()
    guard var queued = responses[key], !queued.isEmpty else {
      return TraversalWorkResult(sourceSpan: span(familyId), referencedFamilyIds: [])
    }
    let response = queued.removeFirst()
    responses[key] = queued
    switch response {
    case .success(let references, let deepSeek, let hiski):
      return TraversalWorkResult(
        sourceSpan: span(familyId), referencedFamilyIds: references,
        deepSeekCalls: deepSeek, hiskiCalls: hiski,
        auditRefs: ["audit:\(familyId.lowercased().replacingOccurrences(of: " ", with: "-"))"])
    case .failure(let failure): throw failure
    }
  }

  private func span(_ familyId: String) -> SourceSpan {
    SourceSpan(
      sourceId: "fixture", sourceSha256: String(repeating: "a", count: 64),
      familyId: familyId, pageReferences: ["1"], startLine: 1, endLine: 2,
      blockSha256: String(repeating: "b", count: 64))
  }
}

@Suite("Traversal session service")
struct TraversalSessionServiceTests {
  private let sourceSHA = String(repeating: "a", count: 64)

  @Test("three-to-five-family traversal stops, resumes, deduplicates, and terminates cycles")
  func boundedResumeAndDeduplication() async throws {
    let worker = StubTraversalWorker([
      "A 1": [.success(["B 1", "C 1", "B 1"])],
      "B 1": [.success(["A 1", "D 1"])],
      "C 1": [.success(["D 1"])],
      "D 1": [.success([])],
    ])
    let store = MemoryTraversalSessionStore()
    let service = TraversalSessionService(worker: worker, store: store, now: { fixedDate })
    let policy = TraversalPolicy(
      maxFamilies: 4, maxDepth: 3, maxItemsPerResume: 1,
      allowedFamilyIds: ["A 1", "B 1", "C 1", "D 1"])

    let started = try await service.start(
      startingFamilyIds: ["A 1"], sourceSHA256: sourceSHA, policy: policy)
    let repeatedStart = try await service.start(
      startingFamilyIds: ["A 1"], sourceSHA256: sourceSHA, policy: policy)
    #expect(repeatedStart.sessionId == started.sessionId)
    #expect(repeatedStart.items.count == 1)

    var session = try await service.resume(sessionId: started.sessionId)
    #expect(session.completedFamilyIds == ["A 1"])
    #expect(session.items.map(\.familyId) == ["A 1", "B 1", "C 1"])
    #expect(session.stopReason == "batch_limit")

    session = try await service.resume(sessionId: started.sessionId)
    session = try await service.resume(sessionId: started.sessionId)
    session = try await service.resume(sessionId: started.sessionId)
    #expect(session.status == .completed)
    #expect(session.items.map(\.familyId) == ["A 1", "B 1", "C 1", "D 1"])
    #expect(Set(await worker.calls) == Set(["A 1", "B 1", "C 1", "D 1"]))

    let idempotentResume = try await service.resume(sessionId: started.sessionId)
    #expect(idempotentResume == session)
    #expect((await worker.calls).count == 4)
  }

  @Test("retryable HiSki failure is checkpointed without losing completed work")
  func retryableFailureDoesNotCorruptProgress() async throws {
    let hiskiFailure = TraversalWorkFailure(
      code: "external_service_unavailable", message: "HiSki timed out", retryable: true)
    let worker = StubTraversalWorker([
      "A 1": [.success(["B 1"])],
      "B 1": [.failure(hiskiFailure), .success([], hiski: 1)],
    ])
    let service = TraversalSessionService(
      worker: worker, store: MemoryTraversalSessionStore(), now: { fixedDate })
    let policy = TraversalPolicy(
      maxFamilies: 2, maxDepth: 1, maxAttemptsPerFamily: 2, maxItemsPerResume: 1,
      maxHiskiCalls: 1, allowedFamilyIds: ["A 1", "B 1"])
    let started = try await service.start(
      startingFamilyIds: ["A 1"], sourceSHA256: sourceSHA, policy: policy)

    _ = try await service.resume(sessionId: started.sessionId)
    var session = try await service.resume(sessionId: started.sessionId)
    #expect(session.completedFamilyIds == ["A 1"])
    #expect(session.items[1].status == .retryPending)
    #expect(session.items[1].lastErrorCode == "external_service_unavailable")

    session = try await service.resume(sessionId: started.sessionId)
    #expect(session.status == .completed)
    #expect(session.completedFamilyIds == ["A 1", "B 1"])
    #expect(session.usage.hiskiCalls == 1)
  }

  @Test("terminal AI failure reports why a family is incomplete")
  func terminalFailureIsVisible() async throws {
    let failure = TraversalWorkFailure(
      code: "malformed_ai_output", message: "DeepSeek JSON failed validation", retryable: false)
    let worker = StubTraversalWorker(["A 1": [.failure(failure)]])
    let service = TraversalSessionService(
      worker: worker, store: MemoryTraversalSessionStore(), now: { fixedDate })
    let policy = TraversalPolicy(
      maxFamilies: 1, maxDepth: 0, maxDeepSeekCalls: 1, allowedFamilyIds: ["A 1"])
    let started = try await service.start(
      startingFamilyIds: ["A 1"], sourceSHA256: sourceSHA, policy: policy)

    let session = try await service.resume(sessionId: started.sessionId)
    #expect(session.status == .incomplete)
    #expect(session.items[0].status == .failed)
    #expect(session.items[0].lastErrorCode == "malformed_ai_output")
    #expect(session.items[0].incompleteReason == "DeepSeek JSON failed validation")
  }

  @Test("file checkpoints survive a new service instance")
  func durableCheckpoint() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("sessions.json")
    let policy = TraversalPolicy(
      maxFamilies: 2, maxDepth: 1, allowedFamilyIds: ["A 1", "B 1"])
    let first = TraversalSessionService(
      worker: StubTraversalWorker(["A 1": [.success(["B 1"])]]),
      store: FileTraversalSessionStore(url: url), now: { fixedDate })
    let started = try await first.start(
      startingFamilyIds: ["A 1"], sourceSHA256: sourceSHA, policy: policy)
    let checkpoint = try await first.resume(sessionId: started.sessionId)
    #expect(checkpoint.completedFamilyIds == ["A 1"])

    let resumed = TraversalSessionService(
      worker: StubTraversalWorker(["B 1": [.success([])]]),
      store: FileTraversalSessionStore(url: url), now: { fixedDate })
    let finished = try await resumed.resume(sessionId: started.sessionId)
    #expect(finished.status == .completed)
    #expect(finished.completedFamilyIds == ["A 1", "B 1"])
  }
}

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
