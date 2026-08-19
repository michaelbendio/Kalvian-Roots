import Foundation
import KalvianRootsCore
import MCP
import XCTest

@testable import KalvianRootsMCPServer

final class KalvianRootsMCPServerTests: XCTestCase {
  private let fixedDate = Date(timeIntervalSince1970: 1_777_777_777)
  private let fixedOperationID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

  func testDiscoveryExposesOnlyGetFamilyText() async throws {
    let session = try await makeSession()
    defer { session.stop() }

    let (tools, nextCursor) = try await session.client.listTools()

    XCTAssertNil(nextCursor)
    XCTAssertEqual(tools.map(\.name), ["get_family_text"])
    XCTAssertEqual(tools.first?.annotations.readOnlyHint, true)
    XCTAssertEqual(tools.first?.annotations.openWorldHint, false)
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

    let unknown = try await session.client.callTool(name: "parse_family")
    let unknownError: ToolErrorEnvelope = try decodeTextContent(unknown.content)
    XCTAssertEqual(unknown.isError, true)
    XCTAssertEqual(unknownError.code, "unsupported_operation")

    let records = await session.auditWriter.records
    XCTAssertEqual(records.map(\.errorCode), ["invalid_request", "unsupported_operation"])
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
    let server = await KalvianRootsMCPServerFactory(
      bookTextService: bookTextService,
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
