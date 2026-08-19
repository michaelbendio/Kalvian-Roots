import CryptoKit
import Foundation
import KalvianRootsCore
import MCP

public let kalvianRootsMCPContractVersion = "1.0"
public let kalvianRootsMCPExecutableVersion = "0.1.0"

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
  public let conflicts: [String]
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
  private let auditWriter: any MCPAuditWriting
  private let now: NowProvider
  private let operationID: OperationIDProvider

  public init(
    bookTextService: any BookTextServing = BookTextService(),
    auditWriter: any MCPAuditWriting = FileMCPAuditWriter(),
    now: @escaping NowProvider = { Date() },
    operationID: @escaping OperationIDProvider = { UUID() }
  ) {
    self.bookTextService = bookTextService
    self.auditWriter = auditWriter
    self.now = now
    self.operationID = operationID
  }

  public func makeServer() async -> Server {
    let server = Server(
      name: "kalvian-roots",
      version: kalvianRootsMCPExecutableVersion,
      title: "Kalvian Roots",
      instructions: "Read exact family blocks from the local canonical Juuret source.",
      capabilities: .init(tools: .init(listChanged: false))
    )

    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: [Self.getFamilyTextTool])
    }

    let bookTextService = self.bookTextService
    let auditWriter = self.auditWriter
    let now = self.now
    let operationID = self.operationID

    await server.withMethodHandler(CallTool.self) { request in
      let id = operationID().uuidString.lowercased()
      let generatedAt = Self.rfc3339(now())

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

  private static func errorResult(
    code: String,
    message: String,
    operationId: String,
    retryable: Bool,
    details: [String: String]?,
    request: CallTool.Parameters,
    generatedAt: String,
    auditWriter: any MCPAuditWriting
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
        externalServicesContacted: [],
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
