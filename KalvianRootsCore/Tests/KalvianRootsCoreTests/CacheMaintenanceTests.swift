import CryptoKit
import Foundation
import XCTest

@testable import KalvianRootsCore

final class CacheMaintenanceTests: XCTestCase {
  func testScopedRefreshReplacesEmbeddedCopiesArchivesDependenciesAndPreservesUnrelatedData()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = try await fixture.book.getFamilyText(familyId: "TEST 1", expectedSourceSHA256: nil)
    let parser = fixture.parser()
    let record = try await parser.parseFamily(source: source, cachePolicy: .refresh)
    // A long-lived reader must observe maintenance, not resurrect its old payload.
    let legacy = LegacyFamilyCacheReader(
      url: fixture.root.appendingPathComponent("Cache/families.json"))
    let observed1 = try await legacy.family(id: "TEST 1")?.primaryCouple?.husband.name
    XCTAssertEqual(observed1, "Old")
    try fixture.write(
      "Cache/person-contexts-v1.json",
      [
        "schemaVersion": 1,
        "contexts": [
          "context-old": ["selectedPerson": ["familyId": "TEST 1"]],
          "context-keep": ["familyId": "OTHER 2"],
        ],
      ])
    try fixture.write(
      "Research/family-comparisons.json",
      [
        "schemaVersion": 1,
        "records": [
          "comparison-old": ["contextId": "context-old"]
        ],
      ])
    let review: [String: Any] = [
      "comparisonId": "comparison-old", "decision": "approved", "note": "Human evidence",
    ]
    try fixture.write(
      "Research/citation-reviews-v1.json",
      [
        "schemaVersion": 1,
        "reviews": [
          "review-old": review, "review-keep": ["familyId": "OTHER 2", "decision": "approved"],
        ],
      ])
    try fixture.write(
      "Traversal/sessions-v1.json",
      [
        "schemaVersion": 1,
        "sessions": [
          "session-old": ["startingFamilyIds": ["TEST 1"]]
        ],
      ])
    try fixture.write(
      "Pilot/reports-v1.json",
      [
        "schemaVersion": 1,
        "reports": [
          "pilot-old": ["traversalSessionId": "session-old", "citationReviewIds": ["review-old"]]
        ],
      ])
    let before = try fixture.read("Cache/families.json")
    let service = fixture.service()
    let audit = try await service.audit(
      familyIds: ["TEST 1"], expectedSourceSHA256: source.source.sha256)
    XCTAssertEqual(audit.totalLegacyNetworks, 3)
    XCTAssertEqual(audit.families[0].legacyNetworkIds, ["CONTAINER 3", "TEST 1"])
    XCTAssertEqual(audit.families[0].nativeRecords.map(\.status), ["current"])
    XCTAssertEqual(audit.dependentRecords["Research/citation-reviews-v1.json"], ["review-old"])
    XCTAssertEqual(audit.dependentRecords["Pilot/reports-v1.json"], ["pilot-old"])
    let callsBefore = await fixture.ai.calls
    let preview = try await service.refresh(
      familyIds: ["TEST 1"], expectedSourceSHA256: source.source.sha256,
      mode: .reparse, dryRun: true)
    XCTAssertEqual(preview.status, "preview")
    let observed2 = await fixture.ai.calls
    XCTAssertEqual(observed2, callsBefore)
    let result = try await service.refresh(
      familyIds: ["TEST 1"], expectedSourceSHA256: source.source.sha256,
      mode: .cached, dryRun: false)
    XCTAssertEqual(result.changedNetworkIds, ["CONTAINER 3", "TEST 1"])
    XCTAssertEqual(result.refreshedFamilies, [record])
    XCTAssertEqual(result.deepSeekCalls, 0)
    let after = try fixture.read("Cache/families.json")
    let oldNetworks = before["families"] as! [String: Any]
    let networks = after["families"] as! [String: Any]
    XCTAssertEqual(try json(oldNetworks["OTHER 2"]!), try json(networks["OTHER 2"]!))
    let rootNetwork = (networks["TEST 1"] as! [String: Any])["network"] as! [String: Any]
    XCTAssertTrue((rootNetwork["asChildFamilies"] as! [String: Any]).isEmpty)
    let container = (networks["CONTAINER 3"] as! [String: Any])["network"] as! [String: Any]
    let embedded = (container["asParentFamilies"] as! [String: Any])["Simo|1710"]!
    XCTAssertEqual(try JSONDecoder().decode(Family.self, from: json(embedded)), record.parsedFamily)
    let observed3 = try await legacy.family(id: "TEST 1")
    XCTAssertEqual(observed3, record.parsedFamily)
    let contexts = try fixture.read("Cache/person-contexts-v1.json")["contexts"] as! [String: Any]
    XCTAssertEqual(Set(contexts.keys), ["context-keep"])
    let activeReviews =
      try fixture.read("Research/citation-reviews-v1.json")["reviews"] as! [String: Any]
    XCTAssertEqual(Set(activeReviews.keys), ["review-keep"])
    let backup = try fixture.read(
      "Maintenance/backups/\(result.backupId!)/before/Research/citation-reviews-v1.json")
    XCTAssertEqual(try json((backup["reviews"] as! [String: Any])["review-old"]!), try json(review))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("Maintenance/pending.json").path))
  }

  func testAuditDistinguishesStaleObsoleteMiskeyedAndLegacyRecords() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = try await fixture.book.getFamilyText(familyId: "TEST 1", expectedSourceSHA256: nil)
    let record = try await fixture.parser().parseFamily(source: source, cachePolicy: .refresh)
    let cache = NativeParsedFamilyCache(
      url: fixture.root.appendingPathComponent("Cache/parsed-families-v1.json"))
    try await cache.store(
      ParsedFamilyRecord(
        familyId: record.familyId, source: record.source, span: record.span,
        parserImplementationVersion: "obsolete", parsedFamily: record.parsedFamily))
    let oldSource = SourceRevision(
      sourceId: source.source.sourceId, fileName: source.source.fileName,
      sha256: String(repeating: "a", count: 64), byteCount: source.source.byteCount,
      loadedAt: source.source.loadedAt, canonicalMarkerValid: true)
    try await cache.store(
      ParsedFamilyRecord(
        familyId: record.familyId, source: oldSource, span: record.span,
        parserImplementationVersion: editorialFamilyParserVersion, parsedFamily: record.parsedFamily
      ))
    var payload = try fixture.read("Cache/parsed-families-v1.json")
    var records = payload["records"] as! [String: Any]
    records["wrong-key"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
    payload["records"] = records
    try fixture.write("Cache/parsed-families-v1.json", payload)
    let other = try await fixture.book.getFamilyText(familyId: "OTHER 2", expectedSourceSHA256: nil)
    try await cache.store(
      ParsedFamilyRecord(
        familyId: other.familyId, source: other.source, span: other.span,
        parserImplementationVersion: "legacy-schema2-unknown",
        parsedFamily: Family(
          familyId: other.familyId,
          pageReferences: ["2"], husband: Person(name: "Juho"), wife: Person(name: "Maria"))))
    let report = try await fixture.service().audit(
      familyIds: ["TEST 1", "OTHER 2"], expectedSourceSHA256: source.source.sha256)
    XCTAssertEqual(
      report.families[0].nativeRecords.map(\.status).sorted(),
      ["current", "invalid_or_obsolete", "invalid_or_obsolete", "stale_source"])
    XCTAssertEqual(report.families[1].nativeRecords.map(\.status), ["legacy_provenance_limited"])
  }

  func testInvalidScopeDesktopGuardAndMalformedCacheDoNotCallAI() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let hash = try await fixture.book.loadSource().sha256
    for ids in [[], ["TEST 1", " test 1 "], Array(repeating: "TEST 1", count: 11)] {
      do {
        _ = try await fixture.service().audit(familyIds: ids, expectedSourceSHA256: hash)
        XCTFail()
      } catch let error as CacheMaintenanceError { XCTAssertEqual(error.code, "invalid_request") }
    }
    do {
      _ = try await fixture.service(running: true).refresh(
        familyIds: ["TEST 1"], expectedSourceSHA256: hash, mode: .reparse, dryRun: false)
      XCTFail()
    } catch let error as CacheMaintenanceError { XCTAssertEqual(error.code, "desktop_app_running") }
    try fixture.write("Cache/parsed-families-v1.json", ["schemaVersion": 999, "records": [:]])
    do {
      _ = try await fixture.service().audit(familyIds: ["TEST 1"], expectedSourceSHA256: hash)
      XCTFail()
    } catch let error as CacheMaintenanceError { XCTAssertEqual(error.code, "cache_unreadable") }
    let observed4 = await fixture.ai.calls
    XCTAssertEqual(observed4, 0)
  }

  func testParseFailureAndConcurrentEditsLeaveActiveCachesUntouched() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let hash = try await fixture.book.loadSource().sha256
    let original = try Data(contentsOf: fixture.root.appendingPathComponent("Cache/families.json"))
    let bad = MaintenanceAI(response: "not JSON")
    do {
      _ = try await fixture.service(ai: bad).refresh(
        familyIds: ["TEST 1"], expectedSourceSHA256: hash, mode: .reparse, dryRun: false)
      XCTFail()
    } catch let error as CacheRefreshFailure {
      XCTAssertTrue(error.cause is FamilyParsingError)
      XCTAssertEqual(error.deepSeekCalls, 1)
    }
    XCTAssertEqual(
      try Data(contentsOf: fixture.root.appendingPathComponent("Cache/families.json")), original)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("Cache/parsed-families-v1.json").path))
    let mutation = MutatingAI(
      response: fixture.response, url: fixture.root.appendingPathComponent("Cache/families.json"),
      data: original + Data("\n".utf8))
    do {
      _ = try await fixture.service(ai: mutation).refresh(
        familyIds: ["TEST 1"], expectedSourceSHA256: hash, mode: .reparse, dryRun: false)
      XCTFail()
    } catch let error as CacheRefreshFailure {
      XCTAssertEqual((error.cause as? CacheMaintenanceError)?.code, "cache_changed")
    }
    XCTAssertEqual(
      try Data(contentsOf: fixture.root.appendingPathComponent("Cache/families.json")),
      original + Data("\n".utf8))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("Cache/parsed-families-v1.json").path))
  }

  func testSecondFamilyFailureCannotInstallFirstStagedFamily() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let hash = try await fixture.book.loadSource().sha256
    let original = try Data(contentsOf: fixture.root.appendingPathComponent("Cache/families.json"))
    // The fixture response is valid only for TEST 1. OTHER 2 fails validation after TEST 1 staged.
    do {
      _ = try await fixture.service().refresh(
        familyIds: ["TEST 1", "OTHER 2"], expectedSourceSHA256: hash,
        mode: .reparse, dryRun: false)
      XCTFail()
    } catch let error as CacheRefreshFailure { XCTAssertEqual(error.deepSeekCalls, 2) }
    XCTAssertEqual(
      try Data(contentsOf: fixture.root.appendingPathComponent("Cache/families.json")), original)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("Cache/parsed-families-v1.json").path))
  }

  func testLockAndInterruptedTransactionRecovery() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.service()
    var lease: CacheAccessLease? = try service.acquireAccess()
    XCTAssertNotNil(lease)
    XCTAssertThrowsError(try service.acquireAccess()) {
      XCTAssertEqual(($0 as? CacheMaintenanceError)?.code, "cache_busy")
    }
    lease = nil
    let path = "Cache/families.json"
    let original = try Data(contentsOf: fixture.root.appendingPathComponent(path))
    let changed = Data("{}".utf8)
    let id = UUID().uuidString
    let backup = fixture.root.appendingPathComponent("Maintenance/backups/\(id)/before/\(path)")
    try FileManager.default.createDirectory(
      at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
    try original.write(to: backup)
    try changed.write(to: fixture.root.appendingPathComponent(path))
    try fixture.write(
      "Maintenance/pending.json",
      [
        "backupId": id, "sourceSHA256": String(repeating: "a", count: 64), "familyIds": ["TEST 1"],
        "entries": [["path": path, "beforeSHA256": sha(original), "afterSHA256": sha(changed)]],
      ])
    let recovered = try service.acquireAccess()
    withExtendedLifetime(recovered) {
      XCTAssertEqual(try? Data(contentsOf: fixture.root.appendingPathComponent(path)), original)
    }
  }

  func testRecoveryRefusesExternallyChangedFileAndKeepsBackup() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let path = "Cache/families.json"
    let original = try Data(contentsOf: fixture.root.appendingPathComponent(path))
    let id = UUID().uuidString
    let changed = Data("{}".utf8)
    let external = Data("external edit".utf8)
    let backup = fixture.root.appendingPathComponent("Maintenance/backups/\(id)/before/\(path)")
    try FileManager.default.createDirectory(
      at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
    try original.write(to: backup)
    try external.write(to: fixture.root.appendingPathComponent(path))
    try fixture.write(
      "Maintenance/pending.json",
      [
        "backupId": id, "sourceSHA256": String(repeating: "a", count: 64), "familyIds": ["TEST 1"],
        "entries": [["path": path, "beforeSHA256": sha(original), "afterSHA256": sha(changed)]],
      ])
    XCTAssertThrowsError(try fixture.service().acquireAccess()) {
      XCTAssertEqual(($0 as? CacheMaintenanceError)?.code, "cache_recovery_required")
    }
    XCTAssertEqual(try Data(contentsOf: fixture.root.appendingPathComponent(path)), external)
    XCTAssertEqual(try Data(contentsOf: backup), original)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("Maintenance/pending.json").path))
  }

  func testSourceChangeDuringParsingCannotInstallAndOldHashIsRejected() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let hash = try await fixture.book.loadSource().sha256
    let sourceURL = fixture.root.appendingPathComponent(canonicalRootsFileName)
    let mutation = MutatingAI(
      response: fixture.response, url: sourceURL,
      data: try Data(contentsOf: sourceURL) + Data("\n".utf8))
    do {
      _ = try await fixture.service(ai: mutation).refresh(
        familyIds: ["TEST 1"], expectedSourceSHA256: hash, mode: .reparse, dryRun: false)
      XCTFail()
    } catch let error as CacheRefreshFailure {
      XCTAssertEqual((error.cause as? CacheMaintenanceError)?.code, "cache_changed")
    }
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("Cache/parsed-families-v1.json").path))
    do {
      _ = try await fixture.service().audit(familyIds: ["TEST 1"], expectedSourceSHA256: hash)
      XCTFail()
    } catch let error as BookTextError { XCTAssertEqual(error.code, "source_changed") }
  }

  func testPreviewUsesCurrentRecordsWithoutParsingOrWritesAndRetainsEditorialAndParentRules()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = try await fixture.book.getFamilyText(familyId: "TEST 1", expectedSourceSHA256: nil)
    let parser = fixture.parser()
    _ = try await parser.parseFamily(source: source, cachePolicy: .refresh)
    let cacheURL = fixture.root.appendingPathComponent("Cache/parsed-families-v1.json")
    let before = try Data(contentsOf: cacheURL)
    let preview = CitationPreviewService(book: fixture.book, parser: parser)
    let child = PersonReference(
      familyId: "TEST 1", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Simo", rawBirthDate: "1710")
    let result = try await preview.preview(
      person: child,
      limits: TraversalLimits(maxFamilies: 1, maxDepth: 0, maxElapsedSeconds: 10),
      expectedSourceSHA256: source.source.sha256)
    XCTAssertTrue(result.proposal.requiresApproval)
    XCTAssertTrue(result.proposal.renderedText.contains("Research correction, 2026-09-11"))
    XCTAssertTrue(result.context.externalServicesContacted.isEmpty)
    XCTAssertEqual(try Data(contentsOf: cacheURL), before)
    let observed5 = await fixture.ai.calls
    XCTAssertEqual(observed5, 1)
    let parent = PersonReference(
      familyId: "TEST 1", coupleIndex: 0, role: .parent, personIndex: 0, rawName: "Lauri")
    do {
      _ = try await preview.preview(
        person: parent, limits: TraversalLimits(maxFamilies: 1, maxDepth: 0, maxElapsedSeconds: 10),
        expectedSourceSHA256: source.source.sha256)
      XCTFail()
    } catch let error as CitationServiceError {
      guard case .asChildCitationRequired = error else { return XCTFail("\(error)") }
    }
    // Same already-loaded parser sees removal; preview must fail without falling back to legacy or AI.
    try fixture.write("Cache/parsed-families-v1.json", ["schemaVersion": 1, "records": [:]])
    do {
      _ = try await preview.preview(
        person: child, limits: TraversalLimits(maxFamilies: 1, maxDepth: 0, maxElapsedSeconds: 10),
        expectedSourceSHA256: source.source.sha256)
      XCTFail()
    } catch let error as FamilyParsingError { XCTAssertEqual(error.code, "cache_miss") }
    let observed6 = await fixture.ai.calls
    XCTAssertEqual(observed6, 1)
  }

  private func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
  }
  private func sha(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct Fixture {
  let root: URL
  let book: BookTextService
  let response: String
  let ai: MaintenanceAI
  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceURL = root.appendingPathComponent(canonicalRootsFileName)
    try Data(
      """
      canonical
      TEST 1, page 1
      ★ Lauri
      ★ Vappu
      Lapset
      ★ 1710 Simo
      Research correction, 2026-09-11 (editorial): Old spouse reference withdrawn.

      OTHER 2, page 2
      ★ Juho
      ★ Maria
      """.utf8
    ).write(to: sourceURL)
    book = BookTextService(locator: ExplicitBookSourceLocator(url: sourceURL, sourceId: "test"))
    let fresh = Family(
      familyId: "TEST 1", pageReferences: ["1"], husband: Person(name: "Lauri"),
      wife: Person(name: "Vappu"), children: [Person(name: "Simo", birthDate: "1710")])
    response = String(decoding: try JSONEncoder().encode(fresh), as: UTF8.self)
    ai = MaintenanceAI(response: response)
    let old = Family(
      familyId: "TEST 1", pageReferences: ["1"], husband: Person(name: "Old", asChild: "OTHER 2"),
      wife: Person(name: "Vappu"))
    let other = Family(
      familyId: "OTHER 2", pageReferences: ["2"], husband: Person(name: "Juho"),
      wife: Person(name: "Maria"))
    let container = Family(
      familyId: "CONTAINER 3", pageReferences: ["3"], husband: Person(name: "Matti"),
      wife: Person(name: "Liisa"))
    func object(_ family: Family) throws -> Any {
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(family))
    }
    func network(_ main: Family, parents: [String: Any] = [:], children: [String: Any] = [:]) throws
      -> [String: Any]
    {
      [
        "cachedAt": "2026-09-10T00:00:00Z", "extractionTime": 10,
        "network": [
          "mainFamily": try object(main), "asChildFamilies": parents, "asParentFamilies": children,
          "spouseAsChildFamilies": [String: Any](),
        ],
      ]
    }
    try write(
      "Cache/families.json",
      [
        "schemaVersion": 2,
        "families": [
          "TEST 1": try network(old, parents: ["Old": object(other)]),
          "OTHER 2": try network(other),
          "CONTAINER 3": try network(container, children: ["Simo|1710": object(old)]),
        ],
      ])
  }
  func parser() -> FamilyParsingService {
    FamilyParsingService(
      ai: ai,
      nativeCache: NativeParsedFamilyCache(
        url: root.appendingPathComponent("Cache/parsed-families-v1.json")),
      legacyCache: LegacyFamilyCacheReader(url: root.appendingPathComponent("Cache/families.json")))
  }
  func service(running: Bool = false, ai: (any FamilyAIResponding)? = nil)
    -> CacheMaintenanceService
  {
    CacheMaintenanceService(
      root: root, book: book, ai: ai ?? self.ai, desktopIsRunning: { running })
  }
  func write(_ path: String, _ object: [String: Any]) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object, options: .sortedKeys).write(
      to: url, options: .atomic)
  }
  func read(_ path: String) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(path)))
      as! [String: Any]
  }
  func remove() { try? FileManager.default.removeItem(at: root) }
}
private actor MaintenanceAI: FamilyAIResponding {
  let response: String
  var calls = 0
  init(response: String) { self.response = response }
  func parseFamily(familyId: String, familyText: String) throws -> String {
    calls += 1
    return response
  }
}
private struct MutatingAI: FamilyAIResponding {
  let response: String, url: URL, data: Data
  func parseFamily(familyId: String, familyText: String) throws -> String {
    try data.write(to: url)
    return response
  }
}
