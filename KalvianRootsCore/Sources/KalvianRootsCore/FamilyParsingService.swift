import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public let juuretFamilySchemaVersion = "juuret-family/1"
public let familyParserImplementationVersion = "deepseek-chat-prompt-2026-08-19"

public enum ParseCachePolicy: String, Codable, Sendable {
  case useValidated
  case refresh
  case cacheOnly
}

public struct ParsingWarning: Codable, Equatable, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct ParsedFamilyRecord: Codable, Equatable, Sendable {
  public let found: Bool
  public let familyId: String
  public let source: SourceRevision
  public let span: SourceSpan
  public let familySchemaVersion: String
  public let parserImplementationVersion: String
  public let parsedFamily: Family
  public let warnings: [ParsingWarning]

  public init(
    familyId: String,
    source: SourceRevision,
    span: SourceSpan,
    parserImplementationVersion: String,
    parsedFamily: Family,
    warnings: [ParsingWarning] = []
  ) {
    self.found = true
    self.familyId = familyId
    self.source = source
    self.span = span
    self.familySchemaVersion = juuretFamilySchemaVersion
    self.parserImplementationVersion = parserImplementationVersion
    self.parsedFamily = parsedFamily
    self.warnings = warnings
  }
}

public enum FamilyParsingError: Error, Equatable, Sendable {
  case cacheMiss(String)
  case malformedAIResponse(String)
  case unsupportedSchema(String)
  case validationFailed([String])
  case credentialUnavailable
  case aiRequestFailed(String)
  case cacheUnreadable(String)

  public var code: String {
    switch self {
    case .cacheMiss: "cache_miss"
    case .malformedAIResponse: "malformed_ai_response"
    case .unsupportedSchema: "unsupported_schema"
    case .validationFailed: "family_validation_failed"
    case .credentialUnavailable: "credential_unavailable"
    case .aiRequestFailed: "ai_request_failed"
    case .cacheUnreadable: "cache_unreadable"
    }
  }
}

extension FamilyParsingError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .cacheMiss(let familyId): "No validated parsed family is cached for \(familyId)."
    case .malformedAIResponse(let reason): "DeepSeek returned malformed family JSON: \(reason)"
    case .unsupportedSchema(let version): "Unsupported family schema: \(version)"
    case .validationFailed(let reasons): "Parsed family validation failed: \(reasons.joined(separator: "; "))"
    case .credentialUnavailable: "The local DeepSeek credential is not configured."
    case .aiRequestFailed(let reason): "The DeepSeek request failed: \(reason)"
    case .cacheUnreadable(let reason): "The parsed-family cache could not be read: \(reason)"
    }
  }
}

public protocol FamilyAIResponding: Sendable {
  func parseFamily(familyId: String, familyText: String) async throws -> String
}

public protocol FamilyParsingServing: Sendable {
  func parseFamily(source: FamilyTextRecord, cachePolicy: ParseCachePolicy) async throws -> ParsedFamilyRecord
  func getParsedFamily(familyId: String, sourceSHA256: String) async throws -> ParsedFamilyRecord?
}

public actor NativeParsedFamilyCache {
  private struct Payload: Codable { let schemaVersion: Int; var records: [String: ParsedFamilyRecord] }
  private let url: URL
  private let fileManager: FileManager
  private var loaded: Payload?

  public init(url: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.url = url ?? Self.defaultURL(fileManager: fileManager)
  }

  public func record(familyId: String, sourceSHA256: String, parserVersion: String) throws -> ParsedFamilyRecord? {
    let payload = try load()
    return payload.records[Self.key(familyId, sourceSHA256, parserVersion)]
  }

  public func store(_ record: ParsedFamilyRecord) throws {
    var payload = try load()
    payload.records[Self.key(record.familyId, record.source.sha256, record.parserImplementationVersion)] = record
    let directory = url.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(payload).write(to: url, options: [.atomic])
    loaded = payload
  }

  private func load() throws -> Payload {
    if let loaded { return loaded }
    guard fileManager.fileExists(atPath: url.path) else {
      let payload = Payload(schemaVersion: 1, records: [:])
      loaded = payload
      return payload
    }
    do {
      let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
      guard payload.schemaVersion == 1 else {
        throw FamilyParsingError.unsupportedSchema("parsed-family-cache/\(payload.schemaVersion)")
      }
      loaded = payload
      return payload
    } catch let error as FamilyParsingError { throw error }
    catch { throw FamilyParsingError.cacheUnreadable(error.localizedDescription) }
  }

  private static func key(_ familyId: String, _ sourceSHA256: String, _ parserVersion: String) -> String {
    "\(familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(sourceSHA256)|\(juuretFamilySchemaVersion)|\(parserVersion)"
  }

  private static func defaultURL(fileManager: FileManager) -> URL {
    guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      fatalError("Application Support directory is unavailable")
    }
    return support.appendingPathComponent("Kalvian Roots/Cache/parsed-families-v1.json")
  }
}

public actor LegacyFamilyCacheReader {
  private let url: URL
  private var payload: [String: Any]?

  public init(url: URL? = nil, fileManager: FileManager = .default) {
    if let url { self.url = url }
    else {
      guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        fatalError("Application Support directory is unavailable")
      }
      self.url = support.appendingPathComponent("Kalvian Roots/Cache/families.json")
    }
  }

  public func family(id: String) throws -> Family? {
    let root = try load()
    if root.isEmpty { return nil }
    guard let version = root["schemaVersion"] as? Int else {
      throw FamilyParsingError.cacheUnreadable("Legacy cache has no schemaVersion.")
    }
    guard version == 2 else { throw FamilyParsingError.unsupportedSchema("legacy-family-cache/\(version)") }
    guard let families = root["families"] as? [String: Any] else {
      throw FamilyParsingError.cacheUnreadable("Legacy cache has no families object.")
    }
    let key = id.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard let cached = families[key] as? [String: Any] else { return nil }
    guard let network = cached["network"] as? [String: Any], let main = network["mainFamily"] else {
      throw FamilyParsingError.cacheUnreadable("Legacy entry \(key) has no network.mainFamily.")
    }
    do {
      let data = try JSONSerialization.data(withJSONObject: main)
      return try JSONDecoder().decode(Family.self, from: data)
    } catch {
      throw FamilyParsingError.cacheUnreadable("Legacy entry \(key) is malformed: \(error.localizedDescription)")
    }
  }

  private func load() throws -> [String: Any] {
    if let payload { return payload }
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    do {
      guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
        throw FamilyParsingError.cacheUnreadable("Legacy cache root is not an object.")
      }
      payload = root
      return root
    } catch let error as FamilyParsingError { throw error }
    catch { throw FamilyParsingError.cacheUnreadable(error.localizedDescription) }
  }
}

public actor FamilyParsingService: FamilyParsingServing {
  private let ai: any FamilyAIResponding
  private let nativeCache: NativeParsedFamilyCache
  private let legacyCache: LegacyFamilyCacheReader

  public init(
    ai: any FamilyAIResponding,
    nativeCache: NativeParsedFamilyCache = NativeParsedFamilyCache(),
    legacyCache: LegacyFamilyCacheReader = LegacyFamilyCacheReader()
  ) {
    self.ai = ai
    self.nativeCache = nativeCache
    self.legacyCache = legacyCache
  }

  public func parseFamily(source: FamilyTextRecord, cachePolicy: ParseCachePolicy) async throws -> ParsedFamilyRecord {
    if cachePolicy != .refresh,
      let native = try await nativeCache.record(
        familyId: source.familyId,
        sourceSHA256: source.source.sha256,
        parserVersion: familyParserImplementationVersion
      ) {
      return native
    }
    if cachePolicy != .refresh,
      let imported = try await nativeCache.record(
        familyId: source.familyId,
        sourceSHA256: source.source.sha256,
        parserVersion: "legacy-schema2-unknown"
      ) {
      return imported
    }

    if cachePolicy != .refresh, let legacy = try await legacyCache.family(id: source.familyId) {
      try Self.validate(legacy, against: source)
      let record = ParsedFamilyRecord(
        familyId: source.familyId,
        source: source.source,
        span: source.span,
        parserImplementationVersion: "legacy-schema2-unknown",
        parsedFamily: legacy,
        warnings: [
          ParsingWarning(
            code: "legacy_cache_provenance_limited",
            message: "Imported from schema-2 families.json; raw DeepSeek response, original source hash, prompt version, and parser version were not stored."
          )
        ]
      )
      try await nativeCache.store(record)
      return record
    }

    guard cachePolicy != .cacheOnly else { throw FamilyParsingError.cacheMiss(source.familyId) }
    let response = try await ai.parseFamily(familyId: source.familyId, familyText: source.rawText)
    let family = try FamilyJSONDecoder.decode(response, expectedFamilyId: source.familyId)
    try Self.validate(family, against: source)
    let record = ParsedFamilyRecord(
      familyId: source.familyId,
      source: source.source,
      span: source.span,
      parserImplementationVersion: familyParserImplementationVersion,
      parsedFamily: family
    )
    try await nativeCache.store(record)
    return record
  }

  public func getParsedFamily(familyId: String, sourceSHA256: String) async throws -> ParsedFamilyRecord? {
    if let current = try await nativeCache.record(
      familyId: familyId,
      sourceSHA256: sourceSHA256,
      parserVersion: familyParserImplementationVersion
    ) { return current }
    return try await nativeCache.record(
      familyId: familyId,
      sourceSHA256: sourceSHA256,
      parserVersion: "legacy-schema2-unknown"
    )
  }

  private static func validate(_ family: Family, against source: FamilyTextRecord) throws {
    var issues: [String] = []
    if family.familyId.isEmpty { issues.append("Family ID is required") }
    if family.pageReferences.isEmpty { issues.append("Page references are required") }
    if family.couples.isEmpty { issues.append("At least one couple is required") }
    for (index, couple) in family.couples.enumerated() {
      if couple.husband.name.isEmpty { issues.append("Couple \(index + 1): Husband name is required") }
      if couple.wife.name.isEmpty { issues.append("Couple \(index + 1): Wife name is required") }
    }
    if family.familyId.caseInsensitiveCompare(source.familyId) != .orderedSame {
      issues.append("Family ID \(family.familyId) does not match source \(source.familyId)")
    }
    if family.pageReferences != source.span.pageReferences {
      issues.append("Page references do not match the source header")
    }
    if !issues.isEmpty { throw FamilyParsingError.validationFailed(issues) }
  }
}

public enum FamilyJSONDecoder {
  public static func decode(_ response: String, expectedFamilyId: String) throws -> Family {
    let cleaned = clean(response)
    guard let data = cleaned.data(using: .utf8) else {
      throw FamilyParsingError.malformedAIResponse("Response is not UTF-8.")
    }
    do {
      let object = try JSONSerialization.jsonObject(with: data)
      guard let dictionary = object as? [String: Any] else {
        throw FamilyParsingError.malformedAIResponse("Root must be an object.")
      }
      try validateKeys(dictionary)
      if let schema = dictionary["schemaVersion"] as? String, schema != juuretFamilySchemaVersion {
        throw FamilyParsingError.unsupportedSchema(schema)
      }
      var familyObject = dictionary
      familyObject.removeValue(forKey: "schemaVersion")
      let familyData = try JSONSerialization.data(withJSONObject: familyObject)
      let family = try JSONDecoder().decode(Family.self, from: familyData)
      guard family.familyId.caseInsensitiveCompare(expectedFamilyId) == .orderedSame else {
        throw FamilyParsingError.validationFailed(["Family ID does not match the requested family"])
      }
      return sanitize(family)
    } catch let error as FamilyParsingError { throw error }
    catch { throw FamilyParsingError.malformedAIResponse(error.localizedDescription) }
  }

  private static func clean(_ response: String) -> String {
    var result = response.trimmingCharacters(in: .whitespacesAndNewlines)
    result = result.replacingOccurrences(of: "```json", with: "")
      .replacingOccurrences(of: "```", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let first = result.firstIndex(of: "{"), let last = result.lastIndex(of: "}") {
      result = String(result[first...last])
    }
    return result
  }

  private static func validateKeys(_ family: [String: Any]) throws {
    let familyKeys: Set<String> = [
      "schemaVersion", "familyId", "pageReferences", "couples", "notes", "noteDefinitions",
    ]
    let coupleKeys: Set<String> = [
      "husband", "wife", "marriageDate", "fullMarriageDate", "children",
      "childrenDiedInfancy", "coupleNotes",
    ]
    let personKeys: Set<String> = [
      "name", "patronymic", "birthDate", "deathDate", "marriageDate",
      "fullMarriageDate", "spouse", "asChild", "asParent", "familySearchId",
      "spouseFamilySearchId", "noteMarkers", "fatherName", "motherName",
      "spouseBirthDate", "spouseParentsFamilyId",
    ]
    try rejectUnexpected(family, allowed: familyKeys, path: "$.")
    guard let couples = family["couples"] as? [[String: Any]] else { return }
    for (coupleIndex, couple) in couples.enumerated() {
      let couplePath = "$.couples[\(coupleIndex)]"
      try rejectUnexpected(couple, allowed: coupleKeys, path: couplePath)
      for role in ["husband", "wife"] {
        if let person = couple[role] as? [String: Any] {
          try rejectUnexpected(person, allowed: personKeys, path: "\(couplePath).\(role)")
        }
      }
      if let children = couple["children"] as? [[String: Any]] {
        for (childIndex, child) in children.enumerated() {
          try rejectUnexpected(
            child, allowed: personKeys, path: "\(couplePath).children[\(childIndex)]"
          )
        }
      }
    }
  }

  private static func rejectUnexpected(
    _ object: [String: Any], allowed: Set<String>, path: String
  ) throws {
    let unexpected = Set(object.keys).subtracting(allowed).sorted()
    if !unexpected.isEmpty {
      throw FamilyParsingError.validationFailed([
        "Unexpected field at \(path): \(unexpected.joined(separator: ", "))"
      ])
    }
  }

  private static func sanitize(_ family: Family) -> Family {
    Family(
      familyId: family.familyId,
      pageReferences: family.pageReferences,
      couples: family.couples.map { couple in
        Couple(
          husband: sanitize(couple.husband), wife: sanitize(couple.wife),
          marriageDate: couple.marriageDate, fullMarriageDate: couple.fullMarriageDate,
          children: couple.children.map(sanitize), childrenDiedInfancy: couple.childrenDiedInfancy,
          coupleNotes: couple.coupleNotes.compactMap(sanitizeField)
        )
      },
      notes: family.notes.compactMap(sanitizeField),
      noteDefinitions: family.noteDefinitions.reduce(into: [:]) { result, entry in
        if let value = sanitizeField(entry.value) { result[entry.key] = value }
      }
    )
  }

  private static func sanitize(_ person: Person) -> Person {
    Person(
      name: person.name, patronymic: person.patronymic, birthDate: person.birthDate,
      deathDate: sanitizeField(person.deathDate), marriageDate: person.marriageDate,
      fullMarriageDate: person.fullMarriageDate, spouse: sanitizeField(person.spouse),
      asChild: sanitizeField(person.asChild), asParent: sanitizeField(person.asParent),
      familySearchId: person.familySearchId, spouseFamilySearchId: person.spouseFamilySearchId,
      noteMarkers: person.noteMarkers, fatherName: person.fatherName, motherName: person.motherName,
      spouseBirthDate: person.spouseBirthDate, spouseParentsFamilyId: person.spouseParentsFamilyId
    )
  }

  private static func sanitizeField(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let pattern = #"(?i)(?:^|\s+)synt\.\s+[^,;\n.]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return trimmed }
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    let cleaned = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty || cleaned.allSatisfy { ".,;".contains($0) } ? nil : cleaned
  }
}
