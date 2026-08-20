import CryptoKit
import Foundation
import KalvianRootsCore
import MCP

public let kalvianRootsMCPContractVersion = "1.0"
public let kalvianRootsMCPExecutableVersion = "0.5.0"

public struct ToolWarning: Codable, Equatable, Sendable {
  public let code: String
  public let message: String
}

public struct ToolEnvelope<Data: Codable & Sendable>: Codable, Sendable {
  public let contractVersion: String
  public let operationId: String
  public let generatedAt: String
  public let tool: String
  public let readOnly: Bool
  public let data: Data
  public let warnings: [ToolWarning]
  public let conflicts: [FactConflict]
  public let provenance: [SourceSpan]
  public let auditRef: String
}

public struct ToolErrorEnvelope: Codable, Equatable, Sendable {
  public let code: String
  public let message: String
  public let operationId: String
  public let retryable: Bool
  public let details: [String: String]?
}

public struct MCPAuditRecord: Codable, Equatable, Sendable {
  public let operationId: String
  public let timestamp: String
  public let tool: String
  public let contractVersion: String
  public let executableVersion: String
  public let request: [String: String]
  public let sourceSHA256: String?
  public let blockSHA256: String?
  public let resultSHA256: String?
  public let cacheStatus: String
  public let externalServicesContacted: [String]
  public let warnings: [String]
  public let conflicts: [String]
  public let status: String
  public let errorCode: String?
}

public protocol MCPAuditWriting: Sendable {
  func append(_ record: MCPAuditRecord) async throws
}

public actor FileMCPAuditWriter: MCPAuditWriting {
  public static let defaultFileName = "mcp-operations.jsonl"

  private let fileURL: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder

  public init(
    fileURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    self.encoder = encoder
  }

  public func append(_ record: MCPAuditRecord) async throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    var data = try encoder.encode(record)
    data.append(0x0A)

    if !fileManager.fileExists(atPath: fileURL.path) {
      try data.write(to: fileURL, options: [.atomic])
      return
    }

    let handle = try FileHandle(forWritingTo: fileURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.synchronize()
  }

  private static func defaultFileURL(fileManager: FileManager) -> URL {
    guard
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      fatalError("Application Support directory is unavailable")
    }

    return
      applicationSupport
      .appendingPathComponent("Kalvian Roots", isDirectory: true)
      .appendingPathComponent("Audit", isDirectory: true)
      .appendingPathComponent(defaultFileName)
  }
}

public actor MemoryMCPAuditWriter: MCPAuditWriting {
  public private(set) var records: [MCPAuditRecord] = []

  public init() {}

  public func append(_ record: MCPAuditRecord) async throws {
    records.append(record)
  }
}

public struct KalvianRootsMCPServerFactory {
  public typealias NowProvider = @Sendable () -> Date
  public typealias OperationIDProvider = @Sendable () -> UUID

  private let bookTextService: any BookTextServing
  private let familyParsingService: any FamilyParsingServing
  private let familyNetworkService: any FamilyNetworkServing
  private let citationService: any CitationServing
  private let personContextStore: any PersonContextStoring
  private let hiskiResearchService: any HiskiResearchServing
  private let auditWriter: any MCPAuditWriting
  private let now: NowProvider
  private let operationID: OperationIDProvider

  public init(
    bookTextService: any BookTextServing = BookTextService(),
    familyParsingService: any FamilyParsingServing = FamilyParsingService(ai: DeepSeekFamilyClient()),
    familyNetworkService: (any FamilyNetworkServing)? = nil,
    citationService: any CitationServing = JuuretCitationService(),
    personContextStore: any PersonContextStoring = FilePersonContextStore(),
    hiskiResearchService: any HiskiResearchServing = HiskiResearchService(),
    auditWriter: any MCPAuditWriting = FileMCPAuditWriter(),
    now: @escaping NowProvider = { Date() },
    operationID: @escaping OperationIDProvider = { UUID() }
  ) {
    self.bookTextService = bookTextService
    self.familyParsingService = familyParsingService
    self.familyNetworkService = familyNetworkService ?? FamilyNetworkService(
      bookTextService: bookTextService, parsingService: familyParsingService
    )
    self.citationService = citationService
    self.personContextStore = personContextStore
    self.hiskiResearchService = hiskiResearchService
    self.auditWriter = auditWriter
    self.now = now
    self.operationID = operationID
  }

  public func makeServer() async -> Server {
    let server = Server(
      name: "kalvian-roots",
      version: kalvianRootsMCPExecutableVersion,
      title: "Kalvian Roots",
      instructions: "Read, parse, resolve, prepare Juuret citations, and research bounded HiSki evidence.",
      capabilities: .init(tools: .init(listChanged: false))
    )

    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: [
        Self.getFamilyTextTool, Self.parseFamilyTool, Self.getParsedFamilyTool,
        Self.resolveFamilyReferencesTool, Self.resolvePersonContextTool,
        Self.generateJuuretCitationTool,
        Self.buildHiskiQueryTool, Self.searchHiskiTool, Self.getHiskiRecordTool,
      ])
    }

    let bookTextService = self.bookTextService
    let familyParsingService = self.familyParsingService
    let familyNetworkService = self.familyNetworkService
    let citationService = self.citationService
    let personContextStore = self.personContextStore
    let hiskiResearchService = self.hiskiResearchService
    let auditWriter = self.auditWriter
    let now = self.now
    let operationID = self.operationID

    await server.withMethodHandler(CallTool.self) { request in
      let id = operationID().uuidString.lowercased()
      let generatedAt = Self.rfc3339(now())

      if request.name == "parse_family" {
        return await Self.handleParseFamily(
          request: request, operationId: id, generatedAt: generatedAt,
          bookTextService: bookTextService, familyParsingService: familyParsingService,
          auditWriter: auditWriter
        )
      }
      if request.name == "get_parsed_family" {
        return await Self.handleGetParsedFamily(
          request: request, operationId: id, generatedAt: generatedAt,
          familyParsingService: familyParsingService, auditWriter: auditWriter
        )
      }
      if request.name == "resolve_family_references" {
        return await Self.handleResolveFamilyReferences(
          request: request, operationId: id, generatedAt: generatedAt,
          bookTextService: bookTextService, familyParsingService: familyParsingService,
          familyNetworkService: familyNetworkService, auditWriter: auditWriter
        )
      }
      if request.name == "generate_juuret_citation" {
        return await Self.handleGenerateJuuretCitation(
          request: request, operationId: id, generatedAt: generatedAt,
          citationService: citationService, personContextStore: personContextStore,
          auditWriter: auditWriter
        )
      }
      if request.name == "build_hiski_query" {
        return await Self.handleBuildHiskiQuery(
          request: request, operationId: id, generatedAt: generatedAt,
          hiskiResearchService: hiskiResearchService, auditWriter: auditWriter
        )
      }
      if request.name == "search_hiski" {
        return await Self.handleSearchHiski(
          request: request, operationId: id, generatedAt: generatedAt,
          hiskiResearchService: hiskiResearchService, auditWriter: auditWriter
        )
      }
      if request.name == "get_hiski_record" {
        return await Self.handleGetHiskiRecord(
          request: request, operationId: id, generatedAt: generatedAt,
          hiskiResearchService: hiskiResearchService, auditWriter: auditWriter
        )
      }
      if request.name == "resolve_person_context" {
        return await Self.handleResolvePersonContext(
          request: request, operationId: id, generatedAt: generatedAt,
          bookTextService: bookTextService, familyParsingService: familyParsingService,
          familyNetworkService: familyNetworkService, personContextStore: personContextStore,
          auditWriter: auditWriter
        )
      }

      guard request.name == "get_family_text" else {
        return await Self.errorResult(
          code: "unsupported_operation",
          message: "Unsupported tool: \(request.name)",
          operationId: id,
          retryable: false,
          details: ["tool": request.name],
          request: request,
          generatedAt: generatedAt,
          auditWriter: auditWriter
        )
      }

      let arguments = request.arguments ?? [:]
      let allowedArguments: Set<String> = ["familyId", "expectedSourceSHA256"]
      let unexpected = Set(arguments.keys).subtracting(allowedArguments).sorted()
      guard unexpected.isEmpty else {
        return await Self.errorResult(
          code: "invalid_request",
          message: "Unexpected argument: \(unexpected.joined(separator: ", "))",
          operationId: id,
          retryable: false,
          details: ["arguments": unexpected.joined(separator: ",")],
          request: request,
          generatedAt: generatedAt,
          auditWriter: auditWriter
        )
      }

      guard let familyId = arguments["familyId"]?.stringValue else {
        return await Self.errorResult(
          code: "invalid_request",
          message: "familyId must be a string.",
          operationId: id,
          retryable: false,
          details: ["argument": "familyId"],
          request: request,
          generatedAt: generatedAt,
          auditWriter: auditWriter
        )
      }

      let expectedSourceSHA256: String?
      if let suppliedHash = arguments["expectedSourceSHA256"] {
        guard let hash = suppliedHash.stringValue, Self.isSHA256(hash) else {
          return await Self.errorResult(
            code: "invalid_request",
            message: "expectedSourceSHA256 must be a lowercase SHA-256 string.",
            operationId: id,
            retryable: false,
            details: ["argument": "expectedSourceSHA256"],
            request: request,
            generatedAt: generatedAt,
            auditWriter: auditWriter
          )
        }
        expectedSourceSHA256 = hash
      } else {
        expectedSourceSHA256 = nil
      }

      do {
        let record = try await bookTextService.getFamilyText(
          familyId: familyId,
          expectedSourceSHA256: expectedSourceSHA256
        )
        let auditRef = "audit:\(id)"
        let envelope = ToolEnvelope(
          contractVersion: kalvianRootsMCPContractVersion,
          operationId: id,
          generatedAt: generatedAt,
          tool: request.name,
          readOnly: true,
          data: record,
          warnings: [],
          conflicts: [],
          provenance: [record.span],
          auditRef: auditRef
        )
        let envelopeData = try Self.encode(envelope)
        let auditRecord = MCPAuditRecord(
          operationId: id,
          timestamp: generatedAt,
          tool: request.name,
          contractVersion: kalvianRootsMCPContractVersion,
          executableVersion: kalvianRootsMCPExecutableVersion,
          request: Self.auditRequest(request),
          sourceSHA256: record.source.sha256,
          blockSHA256: record.span.blockSha256,
          resultSHA256: Self.sha256(envelopeData),
          cacheStatus: "not_applicable",
          externalServicesContacted: [],
          warnings: [],
          conflicts: [],
          status: "success",
          errorCode: nil
        )
        try await auditWriter.append(auditRecord)

        let text = String(decoding: envelopeData, as: UTF8.self)
        return try .init(
          content: [.text(text: text, annotations: nil, _meta: nil)],
          structuredContent: envelope,
          isError: false
        )
      } catch let error as BookTextError {
        return await Self.errorResult(
          code: error.code,
          message: error.localizedDescription,
          operationId: id,
          retryable: Self.isRetryable(error),
          details: Self.details(for: error),
          request: request,
          generatedAt: generatedAt,
          auditWriter: auditWriter
        )
      } catch {
        return await Self.errorResult(
          code: "internal_error",
          message: "The operation could not be completed.",
          operationId: id,
          retryable: false,
          details: nil,
          request: request,
          generatedAt: generatedAt,
          auditWriter: auditWriter
        )
      }
    }

    return server
  }

  private static let getFamilyTextTool = Tool(
    name: "get_family_text",
    title: "Get Juuret family text",
    description:
      "Return one exact family block and its source provenance from JuuretKälviällä.roots.",
    inputSchema: .object([
      "type": "object",
      "additionalProperties": false,
      "required": ["familyId"],
      "properties": .object([
        "familyId": .object([
          "type": "string",
          "minLength": 3,
          "maxLength": 80,
          "pattern": #"^\s*[^\r\n]+\s+[0-9]+[A-Za-z]?\s*$"#,
        ]),
        "expectedSourceSHA256": .object([
          "type": "string",
          "pattern": "^[a-f0-9]{64}$",
        ]),
      ]),
    ]),
    annotations: .init(
      title: "Get Juuret family text",
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  private static let parseFamilyTool = Tool(
    name: "parse_family",
    title: "Parse Juuret family",
    description: "Return a validated structured family, using the accumulated local cache before DeepSeek.",
    inputSchema: .object([
      "type": "object", "additionalProperties": false, "required": ["familyId"],
      "properties": .object([
        "familyId": .object(["type": "string", "minLength": 3, "maxLength": 80]),
        "expectedSourceSHA256": .object(["type": "string", "pattern": "^[a-f0-9]{64}$"]),
        "cachePolicy": .object([
          "type": "string", "enum": ["useValidated", "refresh", "cacheOnly"],
          "default": "useValidated",
        ]),
      ]),
    ]),
    annotations: .init(
      title: "Parse Juuret family", readOnlyHint: true, destructiveHint: false,
      idempotentHint: false, openWorldHint: true
    )
  )

  private static let getParsedFamilyTool = Tool(
    name: "get_parsed_family",
    title: "Get cached parsed family",
    description: "Return a source-revision-matched parsed family without network access.",
    inputSchema: .object([
      "type": "object", "additionalProperties": false,
      "required": ["familyId", "sourceSHA256"],
      "properties": .object([
        "familyId": .object(["type": "string", "minLength": 3, "maxLength": 80]),
        "sourceSHA256": .object(["type": "string", "pattern": "^[a-f0-9]{64}$"]),
      ]),
    ]),
    annotations: .init(
      title: "Get cached parsed family", readOnlyHint: true, destructiveHint: false,
      idempotentHint: true, openWorldHint: false
    )
  )

  private static let traversalLimitsSchema: Value = .object([
    "type": "object", "additionalProperties": false,
    "required": ["maxFamilies", "maxDepth", "maxElapsedSeconds"],
    "properties": .object([
      "maxFamilies": .object(["type": "integer", "minimum": 1, "maximum": 25]),
      "maxDepth": .object(["type": "integer", "minimum": 0, "maximum": 10]),
      "maxElapsedSeconds": .object(["type": "integer", "minimum": 1, "maximum": 300]),
    ]),
  ])

  private static let personReferenceSchema: Value = .object([
    "type": "object", "additionalProperties": false,
    "required": ["familyId", "coupleIndex", "role", "personIndex", "rawName"],
    "properties": .object([
      "familyId": .object(["type": "string", "minLength": 3, "maxLength": 80]),
      "coupleIndex": .object(["type": "integer", "minimum": 0]),
      "role": .object(["type": "string", "enum": ["parent", "child", "spouse"]]),
      "personIndex": .object(["type": "integer", "minimum": 0]),
      "rawName": .object(["type": "string", "minLength": 1]),
      "rawBirthDate": .object(["type": "string"]),
      "rawPatronymic": .object(["type": "string"]),
      "familySearchId": .object(["type": "string"]),
    ]),
  ])

  private static let resolveFamilyReferencesTool = Tool(
    name: "resolve_family_references",
    title: "Resolve Juuret family references",
    description: "Follow explicit as_child and as_parent references within supplied bounds and report evidence, cycles, missing targets, and conflicts.",
    inputSchema: .object([
      "type": "object", "additionalProperties": false,
      "required": ["familyId", "limits"],
      "properties": .object([
        "familyId": .object(["type": "string", "minLength": 3, "maxLength": 80]),
        "expectedSourceSHA256": .object(["type": "string", "pattern": "^[a-f0-9]{64}$"]),
        "limits": traversalLimitsSchema,
      ]),
    ]),
    annotations: .init(
      title: "Resolve Juuret family references", readOnlyHint: true,
      destructiveHint: false, idempotentHint: false, openWorldHint: true
    )
  )

  private static let resolvePersonContextTool = Tool(
    name: "resolve_person_context",
    title: "Resolve Juuret person context",
    description: "Resolve one indexed person's explicit family references and return harvested claims with field-level provenance and conflicts.",
    inputSchema: .object([
      "type": "object", "additionalProperties": false,
      "required": ["familyId", "person", "limits"],
      "properties": .object([
        "familyId": .object(["type": "string", "minLength": 3, "maxLength": 80]),
        "expectedSourceSHA256": .object(["type": "string", "pattern": "^[a-f0-9]{64}$"]),
        "person": personReferenceSchema,
        "limits": traversalLimitsSchema,
      ]),
    ]),
    annotations: .init(
      title: "Resolve Juuret person context", readOnlyHint: true,
      destructiveHint: false, idempotentHint: false, openWorldHint: true
    )
  )

  private static let generateJuuretCitationTool = Tool(
    name: "generate_juuret_citation",
    title: "Generate Juuret citation proposal",
    description: "Render a deterministic Juuret citation proposal from a stored resolved person context. The proposal preserves source spans and conflicts and always requires human approval.",
    inputSchema: .object([
      "type": "object", "additionalProperties": false,
      "required": ["contextId", "selectedPerson"],
      "properties": .object([
        "contextId": .object(["type": "string", "minLength": 1]),
        "selectedPerson": personReferenceSchema,
      ]),
    ]),
    annotations: .init(
      title: "Generate Juuret citation proposal", readOnlyHint: true,
      destructiveHint: false, idempotentHint: true, openWorldHint: false
    )
  )

  private static let sourceSpanSchema: Value = .object([
    "type": "object", "additionalProperties": false,
    "required": [
      "sourceId", "sourceSha256", "familyId", "pageReferences", "startLine",
      "endLine", "blockSha256",
    ],
    "properties": .object([
      "sourceId": .object(["type": "string", "minLength": 1]),
      "sourceSha256": .object(["type": "string", "pattern": "^[a-f0-9]{64}$"]),
      "familyId": .object(["type": "string", "minLength": 3]),
      "pageReferences": .object([
        "type": "array", "items": .object(["type": "string"]),
      ]),
      "startLine": .object(["type": "integer", "minimum": 1]),
      "endLine": .object(["type": "integer", "minimum": 1]),
      "blockSha256": .object(["type": "string", "pattern": "^[a-f0-9]{64}$"]),
    ]),
  ])

  private static let hiskiMotivationSchema: Value = .object([
    "type": "object", "additionalProperties": false,
    "required": ["person", "juuretField", "juuretValue", "sourceSpan"],
    "properties": .object([
      "person": personReferenceSchema,
      "juuretField": .object(["type": "string", "minLength": 1]),
      "juuretValue": .object(["type": "string", "minLength": 1]),
      "sourceSpan": sourceSpanSchema,
    ]),
  ])

  private static let hiskiQuerySchema: Value = .object([
    "type": "object", "additionalProperties": false,
    "required": [
      "queryId", "eventType", "requestedPrimaryName", "requestedDate",
      "queryPrimaryName", "queryDate", "searchURL", "motivation",
    ],
    "properties": .object([
      "queryId": .object(["type": "string", "minLength": 1]),
      "eventType": .object(["type": "string", "enum": ["birth", "marriage", "death"]]),
      "requestedPrimaryName": .object(["type": "string", "minLength": 1]),
      "requestedSecondaryName": .object(["type": "string"]),
      "requestedDate": .object(["type": "string", "minLength": 1]),
      "parentBirthYear": .object(["type": "integer"]),
      "queryPrimaryName": .object(["type": "string", "minLength": 1]),
      "querySecondaryName": .object(["type": "string"]),
      "queryDate": .object(["type": "string", "minLength": 1]),
      "searchURL": .object(["type": "string", "minLength": 1]),
      "motivation": hiskiMotivationSchema,
    ]),
  ])

  private static let hiskiCandidateSchema: Value = .object([
    "type": "object", "additionalProperties": false,
    "required": ["candidateId", "eventType", "recordURL", "recordPath", "fields", "rowText"],
    "properties": .object([
      "candidateId": .object(["type": "string", "minLength": 1]),
      "eventType": .object(["type": "string", "enum": ["birth", "marriage", "death"]]),
      "recordURL": .object(["type": "string", "minLength": 1]),
      "recordPath": .object(["type": "string", "minLength": 1]),
      "fields": .object([
        "type": "array",
        "items": .object([
          "type": "object", "additionalProperties": false,
          "required": ["label", "value"],
          "properties": .object([
            "label": .object(["type": "string", "minLength": 1]),
            "value": .object(["type": "string"]),
          ]),
        ]),
      ]),
      "rowText": .object(["type": "string"]),
    ]),
  ])

  private static let buildHiskiQueryTool = Tool(
    name: "build_hiski_query", title: "Build HiSki query",
    description: "Build a deterministic birth, marriage, or death query tied to the Juuret fact that motivated it.",
    inputSchema: .object([
      "type": "object", "additionalProperties": false,
      "required": ["eventType", "primaryName", "date", "motivation"],
      "properties": .object([
        "eventType": .object(["type": "string", "enum": ["birth", "marriage", "death"]]),
        "primaryName": .object(["type": "string", "minLength": 1]),
        "secondaryName": .object(["type": "string"]),
        "date": .object(["type": "string", "minLength": 1]),
        "parentBirthYear": .object(["type": "integer"]),
        "motivation": hiskiMotivationSchema,
      ]),
    ]),
    annotations: .init(
      title: "Build HiSki query", readOnlyHint: true, destructiveHint: false,
      idempotentHint: true, openWorldHint: false)
  )

  private static let searchHiskiTool = Tool(
    name: "search_hiski", title: "Search HiSki",
    description: "Explicitly run a previously built HiSki query and return every date-matching sl.gif candidate without selecting an identity.",
    inputSchema: .object([
      "type": "object", "additionalProperties": false,
      "required": ["query", "allowLiveNetwork"],
      "properties": .object([
        "query": hiskiQuerySchema,
        "allowLiveNetwork": .object(["type": "boolean", "const": true]),
      ]),
    ]),
    annotations: .init(
      title: "Search HiSki", readOnlyHint: true, destructiveHint: false,
      idempotentHint: false, openWorldHint: true)
  )

  private static let getHiskiRecordTool = Tool(
    name: "get_hiski_record", title: "Get HiSki detail record",
    description: "Explicitly retrieve one HiSki sl.gif detail record and its canonical citation link while retaining the motivating Juuret query.",
    inputSchema: .object([
      "type": "object", "additionalProperties": false,
      "required": ["query", "candidate", "allowLiveNetwork"],
      "properties": .object([
        "query": hiskiQuerySchema,
        "candidate": hiskiCandidateSchema,
        "allowLiveNetwork": .object(["type": "boolean", "const": true]),
      ]),
    ]),
    annotations: .init(
      title: "Get HiSki detail record", readOnlyHint: true, destructiveHint: false,
      idempotentHint: false, openWorldHint: true)
  )

  private struct ParsedFamilyNotFound: Codable, Sendable {
    let found: Bool
    init() { found = false }
  }

  private static func handleParseFamily(
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    bookTextService: any BookTextServing,
    familyParsingService: any FamilyParsingServing,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    let arguments = request.arguments ?? [:]
    let unexpected = Set(arguments.keys).subtracting(["familyId", "expectedSourceSHA256", "cachePolicy"]).sorted()
    guard unexpected.isEmpty,
      let familyId = arguments["familyId"]?.stringValue,
      let policy = ParseCachePolicy(rawValue: arguments["cachePolicy"]?.stringValue ?? "useValidated")
    else {
      return await errorResult(
        code: "invalid_request", message: "parse_family arguments are invalid.",
        operationId: operationId, retryable: false, details: nil,
        request: request, generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
    let expectedHash = arguments["expectedSourceSHA256"]?.stringValue
    if let expectedHash, !isSHA256(expectedHash) {
      return await errorResult(
        code: "invalid_request", message: "expectedSourceSHA256 must be a lowercase SHA-256 string.",
        operationId: operationId, retryable: false, details: nil,
        request: request, generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
    do {
      let source = try await bookTextService.getFamilyText(
        familyId: familyId, expectedSourceSHA256: expectedHash
      )
      let preexisting = policy == .refresh ? nil : try await familyParsingService.getParsedFamily(
        familyId: source.familyId, sourceSHA256: source.source.sha256
      )
      let record = try await familyParsingService.parseFamily(source: source, cachePolicy: policy)
      let warningModels = record.warnings.map { ToolWarning(code: $0.code, message: $0.message) }
      let envelope = ToolEnvelope(
        contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
        generatedAt: generatedAt, tool: request.name, readOnly: true, data: record,
        warnings: warningModels, conflicts: [], provenance: [source.span], auditRef: "audit:\(operationId)"
      )
      let data = try encode(envelope)
      let contactedDeepSeek = preexisting == nil && record.parserImplementationVersion != "legacy-schema2-unknown"
      let cacheStatus = preexisting != nil ? "validated_hit"
        : record.parserImplementationVersion == "legacy-schema2-unknown" ? "legacy_import" : "write"
      try await auditWriter.append(MCPAuditRecord(
        operationId: operationId, timestamp: generatedAt, tool: request.name,
        contractVersion: kalvianRootsMCPContractVersion, executableVersion: kalvianRootsMCPExecutableVersion,
        request: auditRequest(request), sourceSHA256: source.source.sha256,
        blockSHA256: source.span.blockSha256, resultSHA256: sha256(data), cacheStatus: cacheStatus,
        externalServicesContacted: contactedDeepSeek ? ["DeepSeek"] : [],
        warnings: warningModels.map(\.code), conflicts: [], status: "success", errorCode: nil
      ))
      return try .init(
        content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
        structuredContent: envelope, isError: false
      )
    } catch let error as BookTextError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: isRetryable(error), details: details(for: error), request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    } catch let error as FamilyParsingError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: error.code == "ai_request_failed", details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    } catch {
      return await errorResult(
        code: "internal_error", message: "The operation could not be completed.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
  }

  private static func handleGetParsedFamily(
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    familyParsingService: any FamilyParsingServing,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    let arguments = request.arguments ?? [:]
    guard Set(arguments.keys).subtracting(["familyId", "sourceSHA256"]).isEmpty,
      let familyId = arguments["familyId"]?.stringValue,
      let sourceHash = arguments["sourceSHA256"]?.stringValue,
      isSHA256(sourceHash)
    else {
      return await errorResult(
        code: "invalid_request", message: "familyId and sourceSHA256 are required.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
    do {
      let record = try await familyParsingService.getParsedFamily(
        familyId: familyId, sourceSHA256: sourceHash
      )
      let resultData: Data
      let structured: Value
      if let record {
        resultData = try encode(ToolEnvelope(
          contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
          generatedAt: generatedAt, tool: request.name, readOnly: true, data: record,
          warnings: record.warnings.map { ToolWarning(code: $0.code, message: $0.message) },
          conflicts: [], provenance: [record.span], auditRef: "audit:\(operationId)"
        ))
      } else {
        resultData = try encode(ToolEnvelope(
          contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
          generatedAt: generatedAt, tool: request.name, readOnly: true,
          data: ParsedFamilyNotFound(), warnings: [], conflicts: [], provenance: [],
          auditRef: "audit:\(operationId)"
        ))
      }
      structured = try JSONDecoder().decode(Value.self, from: resultData)
      try await auditWriter.append(MCPAuditRecord(
        operationId: operationId, timestamp: generatedAt, tool: request.name,
        contractVersion: kalvianRootsMCPContractVersion, executableVersion: kalvianRootsMCPExecutableVersion,
        request: auditRequest(request), sourceSHA256: sourceHash, blockSHA256: record?.span.blockSha256,
        resultSHA256: sha256(resultData), cacheStatus: record == nil ? "miss" : "validated_hit",
        externalServicesContacted: [], warnings: record?.warnings.map(\.code) ?? [], conflicts: [],
        status: "success", errorCode: nil
      ))
      return try .init(
        content: [.text(text: String(decoding: resultData, as: UTF8.self), annotations: nil, _meta: nil)],
        structuredContent: structured, isError: false
      )
    } catch let error as FamilyParsingError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: false, details: nil, request: request, generatedAt: generatedAt,
        auditWriter: auditWriter
      )
    } catch {
      return await errorResult(
        code: "internal_error", message: "The operation could not be completed.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
  }

  private struct ResolveFamilyArguments: Decodable {
    let familyId: String
    let expectedSourceSHA256: String?
    let limits: TraversalLimits
  }

  private struct ResolvePersonArguments: Decodable {
    let familyId: String
    let expectedSourceSHA256: String?
    let person: PersonReference
    let limits: TraversalLimits
  }

  private struct GenerateCitationArguments: Decodable {
    let contextId: String
    let selectedPerson: PersonReference
  }

  private struct BuildHiskiQueryArguments: Decodable {
    let eventType: HiskiEventType
    let primaryName: String
    let secondaryName: String?
    let date: String
    let parentBirthYear: Int?
    let motivation: HiskiQueryMotivation
  }

  private struct SearchHiskiArguments: Decodable {
    let query: HiskiQuery
    let allowLiveNetwork: Bool
  }

  private struct GetHiskiRecordArguments: Decodable {
    let query: HiskiQuery
    let candidate: HiskiResultCandidate
    let allowLiveNetwork: Bool
  }

  private struct PreparedStartingFamily {
    let record: ParsedFamilyRecord
    let cacheStatus: String
    let externalServicesContacted: [String]
  }

  private static func handleResolveFamilyReferences(
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    bookTextService: any BookTextServing,
    familyParsingService: any FamilyParsingServing,
    familyNetworkService: any FamilyNetworkServing,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    let allowed: Set<String> = ["familyId", "expectedSourceSHA256", "limits"]
    guard Set((request.arguments ?? [:]).keys).subtracting(allowed).isEmpty,
      let arguments = try? decodeArguments(ResolveFamilyArguments.self, request: request),
      arguments.limits.isValid,
      arguments.expectedSourceSHA256.map(isSHA256) ?? true
    else {
      return await errorResult(
        code: "invalid_request", message: "resolve_family_references arguments are invalid.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }

    do {
      let prepared = try await prepareStartingFamily(
        familyId: arguments.familyId, expectedSourceSHA256: arguments.expectedSourceSHA256,
        bookTextService: bookTextService, familyParsingService: familyParsingService
      )
      let resolution = try await familyNetworkService.resolveFamilyReferences(
        startingFamily: prepared.record, limits: arguments.limits
      )
      let warnings = toolWarnings(
        records: resolution.families, network: resolution.missingReferences,
        cycles: resolution.cycles
      )
      let envelope = ToolEnvelope(
        contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
        generatedAt: generatedAt, tool: request.name, readOnly: true, data: resolution,
        warnings: warnings, conflicts: resolution.conflicts,
        provenance: uniqueSpans(resolution.families), auditRef: "audit:\(operationId)"
      )
      let data = try encode(envelope)
      let external = Array(Set(
        prepared.externalServicesContacted + resolution.externalServicesContacted
      )).sorted()
      let statuses = [prepared.cacheStatus] + resolution.cacheStatuses
      try await auditWriter.append(MCPAuditRecord(
        operationId: operationId, timestamp: generatedAt, tool: request.name,
        contractVersion: kalvianRootsMCPContractVersion,
        executableVersion: kalvianRootsMCPExecutableVersion,
        request: auditRequest(request), sourceSHA256: prepared.record.source.sha256,
        blockSHA256: prepared.record.span.blockSha256, resultSHA256: sha256(data),
        cacheStatus: cacheSummary(statuses), externalServicesContacted: external,
        warnings: warnings.map(\.code), conflicts: conflictSummary(resolution.conflicts),
        status: "success", errorCode: nil
      ))
      return try .init(
        content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
        structuredContent: envelope, isError: false
      )
    } catch {
      return await networkErrorResult(
        error, request: request, operationId: operationId,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
  }

  private static func handleResolvePersonContext(
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    bookTextService: any BookTextServing,
    familyParsingService: any FamilyParsingServing,
    familyNetworkService: any FamilyNetworkServing,
    personContextStore: any PersonContextStoring,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    let allowed: Set<String> = ["familyId", "expectedSourceSHA256", "person", "limits"]
    guard Set((request.arguments ?? [:]).keys).subtracting(allowed).isEmpty,
      let arguments = try? decodeArguments(ResolvePersonArguments.self, request: request),
      familyKey(arguments.familyId) == familyKey(arguments.person.familyId),
      arguments.limits.isValid,
      arguments.expectedSourceSHA256.map(isSHA256) ?? true
    else {
      return await errorResult(
        code: "invalid_request", message: "resolve_person_context arguments are invalid.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }

    do {
      let prepared = try await prepareStartingFamily(
        familyId: arguments.familyId, expectedSourceSHA256: arguments.expectedSourceSHA256,
        bookTextService: bookTextService, familyParsingService: familyParsingService
      )
      let resolution = try await familyNetworkService.resolvePersonContext(
        person: arguments.person, startingFamily: prepared.record, limits: arguments.limits
      )
      try await personContextStore.store(resolution)
      let warnings = toolWarnings(
        records: resolution.families, network: resolution.missingReferences,
        cycles: resolution.cycles
      )
      let envelope = ToolEnvelope(
        contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
        generatedAt: generatedAt, tool: request.name, readOnly: true, data: resolution,
        warnings: warnings, conflicts: resolution.conflicts,
        provenance: uniqueSpans(resolution.families), auditRef: "audit:\(operationId)"
      )
      let data = try encode(envelope)
      let external = Array(Set(
        prepared.externalServicesContacted + resolution.externalServicesContacted
      )).sorted()
      let statuses = [prepared.cacheStatus] + resolution.cacheStatuses
      try await auditWriter.append(MCPAuditRecord(
        operationId: operationId, timestamp: generatedAt, tool: request.name,
        contractVersion: kalvianRootsMCPContractVersion,
        executableVersion: kalvianRootsMCPExecutableVersion,
        request: auditRequest(request), sourceSHA256: prepared.record.source.sha256,
        blockSHA256: prepared.record.span.blockSha256, resultSHA256: sha256(data),
        cacheStatus: cacheSummary(statuses), externalServicesContacted: external,
        warnings: warnings.map(\.code), conflicts: conflictSummary(resolution.conflicts),
        status: "success", errorCode: nil
      ))
      return try .init(
        content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
        structuredContent: envelope, isError: false
      )
    } catch {
      return await networkErrorResult(
        error, request: request, operationId: operationId,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
  }

  private static func handleGenerateJuuretCitation(
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    citationService: any CitationServing,
    personContextStore: any PersonContextStoring,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    let allowed: Set<String> = ["contextId", "selectedPerson"]
    guard Set((request.arguments ?? [:]).keys).subtracting(allowed).isEmpty,
      let arguments = try? decodeArguments(GenerateCitationArguments.self, request: request),
      !arguments.contextId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return await errorResult(
        code: "invalid_request", message: "generate_juuret_citation arguments are invalid.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }

    do {
      guard let context = try await personContextStore.context(id: arguments.contextId) else {
        throw CitationServiceError.contextNotFound(arguments.contextId)
      }
      let proposal = try citationService.generateJuuretCitation(
        context: context, selectedPerson: arguments.selectedPerson
      )
      let warnings = proposal.warnings.map {
        ToolWarning(code: $0.code, message: $0.message)
      }
      let envelope = ToolEnvelope(
        contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
        generatedAt: generatedAt, tool: request.name, readOnly: true, data: proposal,
        warnings: warnings, conflicts: proposal.conflicts,
        provenance: proposal.sourceSpans, auditRef: "audit:\(operationId)"
      )
      let data = try encode(envelope)
      try await auditWriter.append(MCPAuditRecord(
        operationId: operationId, timestamp: generatedAt, tool: request.name,
        contractVersion: kalvianRootsMCPContractVersion,
        executableVersion: kalvianRootsMCPExecutableVersion,
        request: auditRequest(request), sourceSHA256: proposal.sourceSpans.first?.sourceSha256,
        blockSHA256: proposal.sourceSpans.first?.blockSha256, resultSHA256: sha256(data),
        cacheStatus: "context_hit", externalServicesContacted: [],
        warnings: uniqueWarningCodes(warnings), conflicts: conflictSummary(proposal.conflicts),
        status: "success", errorCode: nil
      ))
      return try .init(
        content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
        structuredContent: envelope, isError: false
      )
    } catch let error as CitationServiceError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: false, details: nil, request: request, generatedAt: generatedAt,
        auditWriter: auditWriter
      )
    } catch {
      return await errorResult(
        code: "internal_error", message: "The operation could not be completed.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
  }

  private static func handleBuildHiskiQuery(
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    hiskiResearchService: any HiskiResearchServing,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    let allowed: Set<String> = [
      "eventType", "primaryName", "secondaryName", "date", "parentBirthYear", "motivation",
    ]
    guard Set((request.arguments ?? [:]).keys).subtracting(allowed).isEmpty,
      let arguments = try? decodeArguments(BuildHiskiQueryArguments.self, request: request)
    else {
      return await errorResult(
        code: "invalid_request", message: "build_hiski_query arguments are invalid.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter)
    }
    do {
      let query = try hiskiResearchService.buildQuery(
        eventType: arguments.eventType, primaryName: arguments.primaryName,
        secondaryName: arguments.secondaryName, date: arguments.date,
        parentBirthYear: arguments.parentBirthYear, motivation: arguments.motivation)
      let envelope = ToolEnvelope(
        contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
        generatedAt: generatedAt, tool: request.name, readOnly: true, data: query,
        warnings: [], conflicts: [FactConflict](), provenance: [query.motivation.sourceSpan],
        auditRef: "audit:\(operationId)")
      return try await successResult(
        envelope: envelope, request: request, operationId: operationId,
        generatedAt: generatedAt, auditWriter: auditWriter, cacheStatus: "not_applicable",
        externalServicesContacted: [])
    } catch let error as HiskiResearchServiceError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: false, details: nil, request: request, generatedAt: generatedAt,
        auditWriter: auditWriter)
    } catch {
      return await errorResult(
        code: "internal_error", message: "The operation could not be completed.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter)
    }
  }

  private static func handleSearchHiski(
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    hiskiResearchService: any HiskiResearchServing,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    let allowed: Set<String> = ["query", "allowLiveNetwork"]
    guard Set((request.arguments ?? [:]).keys).subtracting(allowed).isEmpty,
      let arguments = try? decodeArguments(SearchHiskiArguments.self, request: request)
    else {
      return await errorResult(
        code: "invalid_request", message: "search_hiski arguments are invalid.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter)
    }
    do {
      let result = try await hiskiResearchService.search(
        arguments.query, allowLiveNetwork: arguments.allowLiveNetwork)
      let warnings = result.ambiguous
        ? [ToolWarning(
          code: "ambiguous_hiski_candidates",
          message: "Multiple HiSki rows match the query date; review every candidate.")]
        : []
      let envelope = ToolEnvelope(
        contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
        generatedAt: generatedAt, tool: request.name, readOnly: true, data: result,
        warnings: warnings, conflicts: [FactConflict](),
        provenance: [result.query.motivation.sourceSpan], auditRef: "audit:\(operationId)")
      return try await successResult(
        envelope: envelope, request: request, operationId: operationId,
        generatedAt: generatedAt, auditWriter: auditWriter, cacheStatus: "not_applicable",
        externalServicesContacted: ["hiski.genealogia.fi"])
    } catch let error as HiskiResearchServiceError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: hiskiRetryable(error), details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter,
        externalServicesContacted: arguments.allowLiveNetwork ? ["hiski.genealogia.fi"] : [])
    } catch {
      return await errorResult(
        code: "network_error", message: error.localizedDescription, operationId: operationId,
        retryable: true, details: nil, request: request, generatedAt: generatedAt,
        auditWriter: auditWriter,
        externalServicesContacted: arguments.allowLiveNetwork ? ["hiski.genealogia.fi"] : [])
    }
  }

  private static func handleGetHiskiRecord(
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    hiskiResearchService: any HiskiResearchServing,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    let allowed: Set<String> = ["query", "candidate", "allowLiveNetwork"]
    guard Set((request.arguments ?? [:]).keys).subtracting(allowed).isEmpty,
      let arguments = try? decodeArguments(GetHiskiRecordArguments.self, request: request)
    else {
      return await errorResult(
        code: "invalid_request", message: "get_hiski_record arguments are invalid.",
        operationId: operationId, retryable: false, details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter)
    }
    do {
      let record = try await hiskiResearchService.record(
        for: arguments.candidate, query: arguments.query,
        allowLiveNetwork: arguments.allowLiveNetwork)
      let envelope = ToolEnvelope(
        contractVersion: kalvianRootsMCPContractVersion, operationId: operationId,
        generatedAt: generatedAt, tool: request.name, readOnly: true, data: record,
        warnings: [], conflicts: [FactConflict](),
        provenance: [record.query.motivation.sourceSpan],
        auditRef: "audit:\(operationId)")
      return try await successResult(
        envelope: envelope, request: request, operationId: operationId,
        generatedAt: generatedAt, auditWriter: auditWriter, cacheStatus: "not_applicable",
        externalServicesContacted: ["hiski.genealogia.fi"])
    } catch let error as HiskiResearchServiceError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: hiskiRetryable(error), details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter,
        externalServicesContacted: arguments.allowLiveNetwork ? ["hiski.genealogia.fi"] : [])
    } catch {
      return await errorResult(
        code: "network_error", message: error.localizedDescription, operationId: operationId,
        retryable: true, details: nil, request: request, generatedAt: generatedAt,
        auditWriter: auditWriter,
        externalServicesContacted: arguments.allowLiveNetwork ? ["hiski.genealogia.fi"] : [])
    }
  }

  private static func prepareStartingFamily(
    familyId: String,
    expectedSourceSHA256: String?,
    bookTextService: any BookTextServing,
    familyParsingService: any FamilyParsingServing
  ) async throws -> PreparedStartingFamily {
    let source = try await bookTextService.getFamilyText(
      familyId: familyId, expectedSourceSHA256: expectedSourceSHA256
    )
    let preexisting = try await familyParsingService.getParsedFamily(
      familyId: source.familyId, sourceSHA256: source.source.sha256
    )
    let record = try await familyParsingService.parseFamily(
      source: source, cachePolicy: .useValidated
    )
    if preexisting != nil {
      return PreparedStartingFamily(
        record: record, cacheStatus: "validated_hit", externalServicesContacted: []
      )
    }
    if record.parserImplementationVersion == "legacy-schema2-unknown" {
      return PreparedStartingFamily(
        record: record, cacheStatus: "legacy_import", externalServicesContacted: []
      )
    }
    return PreparedStartingFamily(
      record: record, cacheStatus: "write", externalServicesContacted: ["DeepSeek"]
    )
  }

  private static func networkErrorResult(
    _ error: Error,
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    auditWriter: any MCPAuditWriting
  ) async -> CallTool.Result {
    if let error = error as? BookTextError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: isRetryable(error), details: details(for: error), request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
    if let error = error as? FamilyParsingError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: error.code == "ai_request_failed", details: nil, request: request,
        generatedAt: generatedAt, auditWriter: auditWriter
      )
    }
    if let error = error as? FamilyNetworkError {
      return await errorResult(
        code: error.code, message: error.localizedDescription, operationId: operationId,
        retryable: false, details: nil, request: request, generatedAt: generatedAt,
        auditWriter: auditWriter
      )
    }
    return await errorResult(
      code: "internal_error", message: "The operation could not be completed.",
      operationId: operationId, retryable: false, details: nil, request: request,
      generatedAt: generatedAt, auditWriter: auditWriter
    )
  }

  private static func decodeArguments<T: Decodable>(
    _ type: T.Type, request: CallTool.Parameters
  ) throws -> T {
    try JSONDecoder().decode(type, from: encode(request.arguments ?? [:]))
  }

  private static func toolWarnings(
    records: [ParsedFamilyRecord], network: [NetworkWarning], cycles: [[String]]
  ) -> [ToolWarning] {
    var result = records.flatMap(\.warnings).map { ToolWarning(code: $0.code, message: $0.message) }
    result += network.map { ToolWarning(code: $0.code, message: $0.message) }
    result += cycles.map {
      ToolWarning(code: "cycle_detected", message: "Family-reference cycle: \($0.joined(separator: " -> "))")
    }
    var seen: Set<String> = []
    return result.filter { seen.insert("\($0.code)|\($0.message)").inserted }
  }

  private static func uniqueSpans(_ records: [ParsedFamilyRecord]) -> [SourceSpan] {
    var seen: Set<String> = []
    return records.map(\.span).filter { seen.insert($0.blockSha256).inserted }
  }

  private static func conflictSummary(_ conflicts: [FactConflict]) -> [String] {
    conflicts.map { "\($0.field):\($0.reason)" }
  }

  private static func uniqueWarningCodes(_ warnings: [ToolWarning]) -> [String] {
    var seen: Set<String> = []
    return warnings.map(\.code).filter { seen.insert($0).inserted }
  }

  private static func hiskiRetryable(_ error: HiskiResearchServiceError) -> Bool {
    if case .serverResponse = error { return true }
    return false
  }

  private static func cacheSummary(_ statuses: [String]) -> String {
    var seen: Set<String> = []
    let unique = statuses.filter { seen.insert($0).inserted }
    return unique.isEmpty ? "not_applicable" : unique.joined(separator: ",")
  }

  private static func familyKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  private static func successResult<Data: Codable & Sendable>(
    envelope: ToolEnvelope<Data>,
    request: CallTool.Parameters,
    operationId: String,
    generatedAt: String,
    auditWriter: any MCPAuditWriting,
    cacheStatus: String,
    externalServicesContacted: [String]
  ) async throws -> CallTool.Result {
    let data = try encode(envelope)
    try await auditWriter.append(MCPAuditRecord(
      operationId: operationId, timestamp: generatedAt, tool: request.name,
      contractVersion: kalvianRootsMCPContractVersion,
      executableVersion: kalvianRootsMCPExecutableVersion,
      request: auditRequest(request),
      sourceSHA256: envelope.provenance.first?.sourceSha256,
      blockSHA256: envelope.provenance.first?.blockSha256,
      resultSHA256: sha256(data), cacheStatus: cacheStatus,
      externalServicesContacted: externalServicesContacted,
      warnings: uniqueWarningCodes(envelope.warnings),
      conflicts: conflictSummary(envelope.conflicts), status: "success", errorCode: nil))
    return try .init(
      content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
      structuredContent: envelope, isError: false)
  }

  private static func errorResult(
    code: String,
    message: String,
    operationId: String,
    retryable: Bool,
    details: [String: String]?,
    request: CallTool.Parameters,
    generatedAt: String,
    auditWriter: any MCPAuditWriting,
    externalServicesContacted: [String] = []
  ) async -> CallTool.Result {
    let error = ToolErrorEnvelope(
      code: code,
      message: message,
      operationId: operationId,
      retryable: retryable,
      details: details
    )

    do {
      let data = try encode(error)
      let auditRecord = MCPAuditRecord(
        operationId: operationId,
        timestamp: generatedAt,
        tool: request.name,
        contractVersion: kalvianRootsMCPContractVersion,
        executableVersion: kalvianRootsMCPExecutableVersion,
        request: auditRequest(request),
        sourceSHA256: nil,
        blockSHA256: nil,
        resultSHA256: sha256(data),
        cacheStatus: "not_applicable",
        externalServicesContacted: externalServicesContacted,
        warnings: [],
        conflicts: [],
        status: "error",
        errorCode: code
      )
      try await auditWriter.append(auditRecord)
      return try .init(
        content: [
          .text(
            text: String(decoding: data, as: UTF8.self),
            annotations: nil,
            _meta: nil
          )
        ],
        structuredContent: error,
        isError: true
      )
    } catch {
      let fallback =
        "{\"code\":\"internal_error\",\"message\":\"The operation could not be completed.\",\"operationId\":\"\(operationId)\",\"retryable\":false}"
      return .init(
        content: [.text(text: fallback, annotations: nil, _meta: nil)],
        isError: true
      )
    }
  }

  private static func auditRequest(_ request: CallTool.Parameters) -> [String: String] {
    var result = ["tool": request.name]
    if let familyId = request.arguments?["familyId"]?.stringValue {
      result["familyId"] = familyId
    }
    if let hash = request.arguments?["expectedSourceSHA256"]?.stringValue {
      result["expectedSourceSHA256"] = hash
    }
    if let hash = request.arguments?["sourceSHA256"]?.stringValue {
      result["sourceSHA256"] = hash
    }
    if let policy = request.arguments?["cachePolicy"]?.stringValue {
      result["cachePolicy"] = policy
    }
    if let contextId = request.arguments?["contextId"]?.stringValue {
      result["contextId"] = contextId
    }
    if let limits = request.arguments?["limits"]?.objectValue {
      for name in ["maxFamilies", "maxDepth", "maxElapsedSeconds"] {
        if let value = limits[name]?.intValue { result[name] = String(value) }
      }
    }
    if let person = request.arguments?["person"]?.objectValue {
      for name in ["familyId", "role", "rawName", "rawBirthDate", "familySearchId"] {
        if let value = person[name]?.stringValue { result["person.\(name)"] = value }
      }
      for name in ["coupleIndex", "personIndex"] {
        if let value = person[name]?.intValue { result["person.\(name)"] = String(value) }
      }
    }
    return result
  }

  private static func details(for error: BookTextError) -> [String: String]? {
    switch error {
    case .sourceChanged(let expected, let actual):
      return ["expected": expected, "actual": actual]
    case .resourceLimitExceeded(let actualBytes, let limitBytes):
      return ["actualBytes": String(actualBytes), "limitBytes": String(limitBytes)]
    default:
      return nil
    }
  }

  private static func isRetryable(_ error: BookTextError) -> Bool {
    switch error {
    case .sourceNotConfigured, .sourceUnreadable:
      return true
    default:
      return false
    }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
  }

  private static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func rfc3339(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
