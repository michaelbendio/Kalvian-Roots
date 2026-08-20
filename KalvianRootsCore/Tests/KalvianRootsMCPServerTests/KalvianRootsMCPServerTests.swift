import Foundation
import KalvianRootsCore
import MCP
import XCTest

@testable import KalvianRootsMCPServer

final class KalvianRootsMCPServerTests: XCTestCase {
  private let fixedDate = Date(timeIntervalSince1970: 1_777_777_777)
  private let fixedOperationID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

  func testDiscoveryExposesPhaseSixTools() async throws {
    let session = try await makeSession()
    defer { session.stop() }

    let (tools, nextCursor) = try await session.client.listTools()

    XCTAssertNil(nextCursor)
    XCTAssertEqual(tools.map(\.name), [
      "get_family_text", "parse_family", "get_parsed_family",
      "resolve_family_references", "resolve_person_context",
      "generate_juuret_citation",
      "build_hiski_query", "search_hiski", "get_hiski_record",
    ])
    XCTAssertEqual(tools.first?.annotations.readOnlyHint, true)
    XCTAssertEqual(tools.first?.annotations.openWorldHint, false)
  }

  func testHiskiToolsBuildSearchAndRetrieveWithoutChoosingAmbiguousCandidate() async throws {
    let session = try await makeSession()
    defer { session.stop() }
    let source = try await session.bookTextService.getFamilyText(
      familyId: "SAKERI 4", expectedSourceSHA256: nil)
    let person = PersonReference(
      familyId: "SAKERI 4", coupleIndex: 0, role: .child, personIndex: 0,
      rawName: "Maria", rawBirthDate: "03.03.1756")
    let motivation = HiskiQueryMotivation(
      person: person, juuretField: "birthDate", juuretValue: "03.03.1756",
      sourceSpan: source.span)

    let built = try await session.client.callTool(
      name: "build_hiski_query",
      arguments: [
        "eventType": "birth", "primaryName": "Maria", "date": "03.03.1756",
        "motivation": try Value(motivation),
      ])
    XCTAssertEqual(built.isError, false)
    let builtEnvelope: ToolEnvelope<HiskiQuery> = try decodeTextContent(built.content)
    XCTAssertEqual(builtEnvelope.data.queryDate, "3.3.1756")
    XCTAssertEqual(builtEnvelope.provenance, [source.span])

    let blocked = try await session.client.callTool(
      name: "search_hiski",
      arguments: ["query": try Value(builtEnvelope.data), "allowLiveNetwork": false])
    let blockedError: ToolErrorEnvelope = try decodeTextContent(blocked.content)
    XCTAssertEqual(blockedError.code, "approval_required")

    let searched = try await session.client.callTool(
      name: "search_hiski",
      arguments: ["query": try Value(builtEnvelope.data), "allowLiveNetwork": true])
    XCTAssertEqual(searched.isError, false)
    let searchEnvelope: ToolEnvelope<HiskiSearchResult> = try decodeTextContent(searched.content)
    XCTAssertEqual(searchEnvelope.data.candidateCount, 2)
    XCTAssertTrue(searchEnvelope.data.ambiguous)
    XCTAssertEqual(searchEnvelope.data.candidates.map { $0.fields.last?.value }, ["Maria", "Maria Elisabeta"])
    XCTAssertEqual(searchEnvelope.warnings.map(\.code), ["ambiguous_hiski_candidates"])

    let recordResult = try await session.client.callTool(
      name: "get_hiski_record",
      arguments: [
        "query": try Value(searchEnvelope.data.query),
        "candidate": try Value(searchEnvelope.data.candidates[0]),
        "allowLiveNetwork": true,
      ])
    let recordEnvelope: ToolEnvelope<HiskiRecord> = try decodeTextContent(recordResult.content)
    XCTAssertEqual(recordEnvelope.data.citationURL, "https://hiski.genealogia.fi/hiski?en+t4087076")
    XCTAssertEqual(recordEnvelope.data.query.motivation, builtEnvelope.data.motivation)
    XCTAssertEqual(recordEnvelope.data.candidate.fields.last?.value, "Maria")
    XCTAssertEqual(recordEnvelope.provenance, [builtEnvelope.data.motivation.sourceSpan])

    let audits = await session.auditWriter.records
    XCTAssertEqual(audits.map(\.externalServicesContacted), [
      [], [], ["hiski.genealogia.fi"], ["hiski.genealogia.fi"],
    ])
  }

  func testSakeri4ResponseMatchesBookTextServiceExactly() async throws {
    let session = try await makeSession()
    defer { session.stop() }

    let expected = try await session.bookTextService.getFamilyText(
      familyId: "SAKERI 4",
      expectedSourceSHA256: nil
    )
    let result = try await session.client.callTool(
      name: "get_family_text",
      arguments: ["familyId": "SAKERI 4"]
    )

    XCTAssertEqual(result.isError, false)
    let envelope: ToolEnvelope<FamilyTextRecord> = try decodeTextContent(result.content)
    XCTAssertEqual(envelope.contractVersion, "1.0")
    XCTAssertEqual(envelope.operationId, fixedOperationID.uuidString.lowercased())
    XCTAssertEqual(envelope.tool, "get_family_text")
    XCTAssertTrue(envelope.readOnly)
    XCTAssertEqual(envelope.data, expected)
    XCTAssertEqual(
      Array(envelope.data.source.fileName.utf8),
      Array(canonicalRootsFileName.utf8)
    )
    XCTAssertEqual(envelope.provenance, [expected.span])
    XCTAssertEqual(envelope.auditRef, "audit:\(envelope.operationId)")
    XCTAssertTrue(envelope.warnings.isEmpty)
    XCTAssertTrue(envelope.conflicts.isEmpty)

    let records = await session.auditWriter.records
    let audit = try XCTUnwrap(records.first)
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(audit.status, "success")
    XCTAssertEqual(audit.sourceSHA256, expected.source.sha256)
    XCTAssertEqual(audit.blockSHA256, expected.span.blockSha256)
    XCTAssertEqual(audit.externalServicesContacted, [])
    XCTAssertEqual(audit.cacheStatus, "not_applicable")
  }

  func testExpectedSourceHashIsEnforced() async throws {
    let session = try await makeSession()
    defer { session.stop() }

    let result = try await session.client.callTool(
      name: "get_family_text",
      arguments: [
        "familyId": "SAKERI 4",
        "expectedSourceSHA256": .string(String(repeating: "0", count: 64)),
      ]
    )

    XCTAssertEqual(result.isError, true)
    let error: ToolErrorEnvelope = try decodeTextContent(result.content)
    XCTAssertEqual(error.code, "source_changed")
    XCTAssertFalse(error.retryable)
    XCTAssertEqual(error.details?["expected"], String(repeating: "0", count: 64))

    let records = await session.auditWriter.records
    let audit = try XCTUnwrap(records.first)
    XCTAssertEqual(audit.status, "error")
    XCTAssertEqual(audit.errorCode, "source_changed")
  }

  func testMalformedArgumentsAndUnknownToolsReturnStructuredErrors() async throws {
    let session = try await makeSession()
    defer { session.stop() }

    let malformed = try await session.client.callTool(
      name: "get_family_text",
      arguments: ["familyId": 4]
    )
    let malformedError: ToolErrorEnvelope = try decodeTextContent(malformed.content)
    XCTAssertEqual(malformed.isError, true)
    XCTAssertEqual(malformedError.code, "invalid_request")

    let unknown = try await session.client.callTool(name: "future_tool")
    let unknownError: ToolErrorEnvelope = try decodeTextContent(unknown.content)
    XCTAssertEqual(unknown.isError, true)
    XCTAssertEqual(unknownError.code, "unsupported_operation")

    let records = await session.auditWriter.records
    XCTAssertEqual(records.map(\.errorCode), ["invalid_request", "unsupported_operation"])
  }

  func testParseFamilyAndGetParsedFamilyReturnVersionedStructuredData() async throws {
    let session = try await makeSession()
    defer { session.stop() }
    let source = try await session.bookTextService.getFamilyText(
      familyId: "SAKERI 4", expectedSourceSHA256: nil
    )
    let parsed = try await session.client.callTool(
      name: "parse_family", arguments: ["familyId": "SAKERI 4", "cachePolicy": "cacheOnly"]
    )
    XCTAssertEqual(parsed.isError, false)
    let parsedEnvelope: ToolEnvelope<ParsedFamilyRecord> = try decodeTextContent(parsed.content)
    XCTAssertEqual(parsedEnvelope.data.familySchemaVersion, "juuret-family/1")
    XCTAssertEqual(parsedEnvelope.data.parsedFamily.primaryCouple?.husband.displayName, "Antti Mikonp.")

    let cached = try await session.client.callTool(
      name: "get_parsed_family",
      arguments: ["familyId": "SAKERI 4", "sourceSHA256": .string(source.source.sha256)]
    )
    XCTAssertEqual(cached.isError, false)
    let cachedEnvelope: ToolEnvelope<ParsedFamilyRecord> = try decodeTextContent(cached.content)
    XCTAssertEqual(cachedEnvelope.data, parsedEnvelope.data)
    let audits = await session.auditWriter.records
    XCTAssertEqual(audits.map(\.externalServicesContacted), [[], []])
  }

  func testResolvePersonContextReturnsMariaHarvestedClaimsAndConflict() async throws {
    let session = try await makeSession()
    defer { session.stop() }

    let result = try await session.client.callTool(
      name: "resolve_person_context",
      arguments: [
        "familyId": "SAKERI 4",
        "person": .object([
          "familyId": "SAKERI 4", "coupleIndex": 0, "role": "child",
          "personIndex": 0, "rawName": "Maria", "rawBirthDate": "03.03.1756",
          "familySearchId": "KN1X-VHG",
        ]),
        "limits": .object([
          "maxFamilies": 3, "maxDepth": 3, "maxElapsedSeconds": 10,
        ]),
      ]
    )

    XCTAssertEqual(result.isError, false)
    let envelope: ToolEnvelope<PersonContextResolution> = try decodeTextContent(result.content)
    XCTAssertEqual(envelope.data.families.map(\.familyId), ["SAKERI 4", "PUUKANGAS 6"])
    XCTAssertEqual(
      envelope.data.claims.first { $0.field == "deathDate" }?.value,
      "04.10.1829"
    )
    XCTAssertEqual(
      envelope.data.claims.first {
        $0.field == "marriageDate" && $0.derivation == .referenceHarvested
      }?.value,
      "26.12.1782"
    )
    XCTAssertEqual(envelope.conflicts.map(\.field), ["birthDate"])
    XCTAssertEqual(envelope.provenance.map(\.familyId), ["SAKERI 4", "PUUKANGAS 6"])
    XCTAssertTrue(envelope.warnings.contains { $0.code == "cycle_detected" })

    let audits = await session.auditWriter.records
    let audit = try XCTUnwrap(audits.first)
    XCTAssertEqual(audit.externalServicesContacted, [])
    XCTAssertEqual(audit.conflicts, ["birthDate:source_values_disagree"])
    XCTAssertEqual(audit.request["maxFamilies"], "3")
    XCTAssertEqual(audit.request["maxDepth"], "3")
    XCTAssertEqual(audit.request["person.rawName"], "Maria")
    XCTAssertEqual(audit.request["person.rawBirthDate"], "03.03.1756")
  }

  func testResolveFamilyReferencesReturnsBoundedIncompleteGraph() async throws {
    let session = try await makeSession()
    defer { session.stop() }

    let result = try await session.client.callTool(
      name: "resolve_family_references",
      arguments: [
        "familyId": "SAKERI 4",
        "limits": .object([
          "maxFamilies": 2, "maxDepth": 0, "maxElapsedSeconds": 10,
        ]),
      ]
    )

    XCTAssertEqual(result.isError, false)
    let envelope: ToolEnvelope<FamilyNetworkResolution> = try decodeTextContent(result.content)
    XCTAssertFalse(envelope.data.complete)
    XCTAssertEqual(envelope.data.families.map(\.familyId), ["SAKERI 4"])
    XCTAssertEqual(envelope.data.edges.map(\.status), [.limitReached])
    XCTAssertTrue(envelope.warnings.contains { $0.code == "traversal_limit_reached" })
  }

  func testGenerateJuuretCitationUsesStoredContextAndRequiresApproval() async throws {
    let session = try await makeSession()
    defer { session.stop() }
    let person: Value = .object([
      "familyId": "SAKERI 4", "coupleIndex": 0, "role": "child",
      "personIndex": 0, "rawName": "Maria", "rawBirthDate": "03.03.1756",
      "familySearchId": "KN1X-VHG",
    ])
    let resolved = try await session.client.callTool(
      name: "resolve_person_context",
      arguments: [
        "familyId": "SAKERI 4", "person": person,
        "limits": .object([
          "maxFamilies": 3, "maxDepth": 3, "maxElapsedSeconds": 10,
        ]),
      ]
    )
    let context: ToolEnvelope<PersonContextResolution> = try decodeTextContent(resolved.content)

    let result = try await session.client.callTool(
      name: "generate_juuret_citation",
      arguments: ["contextId": .string(context.data.contextId), "selectedPerson": person]
    )

    XCTAssertEqual(result.isError, false)
    let envelope: ToolEnvelope<CitationProposal> = try decodeTextContent(result.content)
    XCTAssertTrue(envelope.data.requiresApproval)
    XCTAssertTrue(envelope.data.renderedText.contains("→ Maria"))
    XCTAssertTrue(envelope.data.renderedText.contains("4 October 1829"))
    XCTAssertTrue(envelope.data.renderedText.contains("26 December 1782"))
    XCTAssertTrue(envelope.data.renderedText.contains("Additional information:"))
    XCTAssertEqual(envelope.data.sourceSpans.map(\.familyId), ["SAKERI 4", "PUUKANGAS 6"])
    XCTAssertEqual(envelope.data.conflicts.map(\.field), ["birthDate"])
    XCTAssertEqual(envelope.provenance, envelope.data.sourceSpans)

    let audits = await session.auditWriter.records
    XCTAssertEqual(audits.count, 2)
    XCTAssertEqual(audits.last?.tool, "generate_juuret_citation")
    XCTAssertEqual(audits.last?.cacheStatus, "context_hit")
    XCTAssertEqual(audits.last?.externalServicesContacted, [])
    XCTAssertEqual(audits.last?.request["contextId"], context.data.contextId)
  }

  func testGenerateJuuretCitationRejectsUnknownContext() async throws {
    let session = try await makeSession()
    defer { session.stop() }

    let result = try await session.client.callTool(
      name: "generate_juuret_citation",
      arguments: [
        "contextId": "missing-context",
        "selectedPerson": .object([
          "familyId": "SAKERI 4", "coupleIndex": 0, "role": "child",
          "personIndex": 0, "rawName": "Maria",
        ]),
      ]
    )

    XCTAssertEqual(result.isError, true)
    let error: ToolErrorEnvelope = try decodeTextContent(result.content)
    XCTAssertEqual(error.code, "record_not_found")
    XCTAssertFalse(error.retryable)
  }

  func testFileAuditWriterUsesAppendOnlyJSONLines() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("audit.jsonl")
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = FileMCPAuditWriter(fileURL: fileURL)
    let record = MCPAuditRecord(
      operationId: "operation",
      timestamp: "2026-08-19T00:00:00.000Z",
      tool: "get_family_text",
      contractVersion: "1.0",
      executableVersion: "0.1.0",
      request: ["familyId": "SAKERI 4"],
      sourceSHA256: nil,
      blockSHA256: nil,
      resultSHA256: nil,
      cacheStatus: "not_applicable",
      externalServicesContacted: [],
      warnings: [],
      conflicts: [],
      status: "success",
      errorCode: nil
    )

    try await writer.append(record)
    try await writer.append(record)

    let lines = try String(contentsOf: fileURL, encoding: .utf8)
      .split(separator: "\n")
    XCTAssertEqual(lines.count, 2)
    for line in lines {
      XCTAssertEqual(try JSONDecoder().decode(MCPAuditRecord.self, from: Data(line.utf8)), record)
    }
  }

  private func makeSession() async throws -> TestSession {
    let fixtureDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("KalvianRootsCoreTests", isDirectory: true)
      .appendingPathComponent("Fixtures", isDirectory: true)
    let sourceURL = fixtureDirectory.appendingPathComponent("JuuretKälviällä.roots")
    XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))

    let fixedDate = self.fixedDate
    let fixedOperationID = self.fixedOperationID
    let bookTextService = BookTextService(
      locator: ExplicitBookSourceLocator(url: sourceURL, sourceId: "test-source"),
      now: { fixedDate }
    )
    let auditWriter = MemoryMCPAuditWriter()
    let parsingService = StubParsingService()
    let contextStore = MemoryPersonContextStore()
    let server = await KalvianRootsMCPServerFactory(
      bookTextService: bookTextService,
      familyParsingService: parsingService,
      personContextStore: contextStore,
      hiskiResearchService: StubHiskiResearchService(),
      auditWriter: auditWriter,
      now: { fixedDate },
      operationID: { fixedOperationID }
    ).makeServer()
    let pair = await InMemoryTransport.createConnectedPair()
    let client = Client(name: "phase-2-tests", version: "1.0")

    try await server.start(transport: pair.server)
    let initialization = try await client.connect(transport: pair.client)
    XCTAssertEqual(initialization.serverInfo.name, "kalvian-roots")
    XCTAssertNotNil(initialization.capabilities.tools)

    return TestSession(
      server: server,
      client: client,
      bookTextService: bookTextService,
      auditWriter: auditWriter
    )
  }

  private func decodeTextContent<T: Decodable>(_ content: [Tool.Content]) throws -> T {
    guard case .text(let text, _, _) = try XCTUnwrap(content.first) else {
      return try XCTUnwrap(nil as T?, "Expected text tool content")
    }
    return try JSONDecoder().decode(T.self, from: Data(text.utf8))
  }
}

private struct StubHiskiResearchService: HiskiResearchServing {
  private let builder = HiskiResearchService(fetcher: StubHiskiFetcher())

  func buildQuery(
    eventType: HiskiEventType,
    primaryName: String,
    secondaryName: String?,
    date: String,
    parentBirthYear: Int?,
    motivation: HiskiQueryMotivation
  ) throws -> HiskiQuery {
    try builder.buildQuery(
      eventType: eventType, primaryName: primaryName, secondaryName: secondaryName,
      date: date, parentBirthYear: parentBirthYear, motivation: motivation)
  }

  func search(_ query: HiskiQuery, allowLiveNetwork: Bool) async throws -> HiskiSearchResult {
    guard allowLiveNetwork else { throw HiskiResearchServiceError.liveNetworkApprovalRequired }
    let fields1 = [
      HiskiResultField(label: "Born", value: "3.3.1756"),
      HiskiResultField(label: "Child", value: "Maria"),
    ]
    let fields2 = [
      HiskiResultField(label: "Born", value: "3.3.1756"),
      HiskiResultField(label: "Child", value: "Maria Elisabeta"),
    ]
    return HiskiSearchResult(query: query, candidates: [
      HiskiResultCandidate(
        candidateId: "candidate-1", eventType: .birth,
        recordURL: "https://hiski.genealogia.fi/hiski?en+0265+kastetut+3326",
        recordPath: "/hiski?en+0265+kastetut+3326", fields: fields1,
        rowText: "3.3.1756 | Maria"),
      HiskiResultCandidate(
        candidateId: "candidate-2", eventType: .birth,
        recordURL: "https://hiski.genealogia.fi/hiski?en+0165+kastetut+9988",
        recordPath: "/hiski?en+0165+kastetut+9988", fields: fields2,
        rowText: "3.3.1756 | Maria Elisabeta"),
    ], responseSha256: String(repeating: "a", count: 64))
  }

  func record(
    for candidate: HiskiResultCandidate,
    query: HiskiQuery,
    allowLiveNetwork: Bool
  ) async throws -> HiskiRecord {
    guard allowLiveNetwork else { throw HiskiResearchServiceError.liveNetworkApprovalRequired }
    return HiskiRecord(
      query: query, candidate: candidate,
      citationURL: "https://hiski.genealogia.fi/hiski?en+t4087076",
      fields: candidate.fields, recordText: candidate.rowText,
      responseSha256: String(repeating: "b", count: 64))
  }
}

private struct StubHiskiFetcher: HiskiHTMLFetching {
  func html(from url: URL) async throws -> String { "" }
}

private actor StubParsingService: FamilyParsingServing {
  private var records: [String: ParsedFamilyRecord] = [:]

  func parseFamily(source: FamilyTextRecord, cachePolicy: ParseCachePolicy) async throws -> ParsedFamilyRecord {
    let family: Family
    if source.familyId == "PUUKANGAS 6" {
      family = Family(
        familyId: source.familyId, pageReferences: source.span.pageReferences,
        couples: [Couple(
          husband: Person(name: "Juho", patronymic: "Juhonp.", birthDate: "03.09.1754"),
          wife: Person(
            name: "Maria", patronymic: "Antint.", birthDate: "13.03.1756",
            deathDate: "04.10.1829", asChild: "SAKERI 4", familySearchId: "KN1X-VHG"
          ),
          fullMarriageDate: "26.12.1782"
        )]
      )
    } else {
      family = Family(
        familyId: source.familyId, pageReferences: source.span.pageReferences,
        husband: Person(name: "Antti", patronymic: "Mikonp."),
        wife: Person(name: "Brita", patronymic: "Juhont."),
        children: [Person(
          name: "Maria", birthDate: "03.03.1756", marriageDate: "82",
          spouse: "Juho Styrman", asParent: "PUUKANGAS 6", familySearchId: "KN1X-VHG"
        )]
      )
    }
    let record = ParsedFamilyRecord(
      familyId: source.familyId, source: source.source, span: source.span,
      parserImplementationVersion: "legacy-schema2-unknown", parsedFamily: family
    )
    records[key(source.familyId, source.source.sha256)] = record
    return record
  }

  func getParsedFamily(familyId: String, sourceSHA256: String) async throws -> ParsedFamilyRecord? {
    records[key(familyId, sourceSHA256)]
  }

  private func key(_ familyId: String, _ hash: String) -> String { "\(familyId)|\(hash)" }
}

private struct TestSession {
  let server: Server
  let client: Client
  let bookTextService: BookTextService
  let auditWriter: MemoryMCPAuditWriter

  func stop() {
    Task {
      await server.stop()
      await client.disconnect()
    }
  }
}
