import CryptoKit
import Foundation

public let canonicalRootsFileName = "JuuretKälviällä.roots"

public struct SourceRevision: Codable, Equatable, Sendable {
  public let sourceId: String
  public let fileName: String
  public let sha256: String
  public let byteCount: Int
  public let loadedAt: String
  public let canonicalMarkerValid: Bool

  public init(
    sourceId: String,
    fileName: String,
    sha256: String,
    byteCount: Int,
    loadedAt: String,
    canonicalMarkerValid: Bool
  ) {
    self.sourceId = sourceId
    self.fileName = fileName
    self.sha256 = sha256
    self.byteCount = byteCount
    self.loadedAt = loadedAt
    self.canonicalMarkerValid = canonicalMarkerValid
  }
}

public struct SourceSpan: Codable, Equatable, Sendable {
  public let sourceId: String
  public let sourceSha256: String
  public let familyId: String
  public let pageReferences: [String]
  public let startLine: Int
  public let endLine: Int
  public let blockSha256: String

  public init(
    sourceId: String,
    sourceSha256: String,
    familyId: String,
    pageReferences: [String],
    startLine: Int,
    endLine: Int,
    blockSha256: String
  ) {
    self.sourceId = sourceId
    self.sourceSha256 = sourceSha256
    self.familyId = familyId
    self.pageReferences = pageReferences
    self.startLine = startLine
    self.endLine = endLine
    self.blockSha256 = blockSha256
  }
}

public struct FamilyTextRecord: Codable, Equatable, Sendable {
  public let familyId: String
  public let rawText: String
  public let source: SourceRevision
  public let span: SourceSpan

  public init(
    familyId: String,
    rawText: String,
    source: SourceRevision,
    span: SourceSpan
  ) {
    self.familyId = familyId
    self.rawText = rawText
    self.source = source
    self.span = span
  }
}

public enum BookTextError: Error, Equatable, Sendable {
  case invalidFamilyIdentifier(String)
  case sourceNotConfigured
  case sourceUnreadable(String)
  case familyNotFound(String)
  case sourceChanged(expected: String, actual: String)
  case resourceLimitExceeded(actualBytes: Int, limitBytes: Int)

  public var code: String {
    switch self {
    case .invalidFamilyIdentifier:
      return "invalid_family_identifier"
    case .sourceNotConfigured:
      return "source_not_configured"
    case .sourceUnreadable:
      return "source_unreadable"
    case .familyNotFound:
      return "family_not_found"
    case .sourceChanged:
      return "source_changed"
    case .resourceLimitExceeded:
      return "resource_limit_exceeded"
    }
  }
}

extension BookTextError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidFamilyIdentifier(let familyId):
      return "Malformed family identifier: \(familyId)"
    case .sourceNotConfigured:
      return "JuuretKälviällä.roots is not available from the configured source."
    case .sourceUnreadable(let reason):
      return "The configured Juuret source could not be read: \(reason)"
    case .familyNotFound(let familyId):
      return "Family \(familyId) was not found in the configured Juuret source."
    case .sourceChanged(let expected, let actual):
      return "The Juuret source changed (expected \(expected), found \(actual))."
    case .resourceLimitExceeded(let actualBytes, let limitBytes):
      return "The family block is \(actualBytes) bytes; the limit is \(limitBytes) bytes."
    }
  }
}

public protocol BookTextServing: Sendable {
  func loadSource() async throws -> SourceRevision
  func getFamilyText(
    familyId: String,
    expectedSourceSHA256: String?
  ) async throws -> FamilyTextRecord
}

public struct LocatedBookSource: Equatable, Sendable {
  public let url: URL
  public let sourceId: String

  public init(url: URL, sourceId: String) {
    self.url = url
    self.sourceId = sourceId
  }
}

public protocol BookSourceLocating: Sendable {
  func locateSource() throws -> LocatedBookSource
}

public struct DocumentsBookSourceLocator: BookSourceLocating {
  private let documentsDirectory: URL?

  public init(
    documentsDirectory: URL? = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first
  ) {
    self.documentsDirectory = documentsDirectory
  }

  public func locateSource() throws -> LocatedBookSource {
    guard let documentsDirectory else {
      throw BookTextError.sourceNotConfigured
    }

    let url = documentsDirectory.appendingPathComponent(canonicalRootsFileName)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw BookTextError.sourceNotConfigured
    }

    return LocatedBookSource(url: url, sourceId: "local-documents")
  }
}

public struct ExplicitBookSourceLocator: BookSourceLocating {
  private let url: URL
  private let sourceId: String

  public init(url: URL, sourceId: String? = nil) {
    self.url = url
    self.sourceId = sourceId ?? Self.sourceId(for: url)
  }

  public static func sourceId(for url: URL) -> String {
    let pathHash = sha256Hex(Data(url.standardizedFileURL.path.utf8))
    return "explicit-selection:\(pathHash)"
  }

  public func locateSource() throws -> LocatedBookSource {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw BookTextError.sourceNotConfigured
    }
    return LocatedBookSource(url: url, sourceId: sourceId)
  }
}

public protocol BookDataReading: Sendable {
  func readData(from url: URL) throws -> Data
}

public struct FoundationBookDataReader: BookDataReading {
  public init() {}

  public func readData(from url: URL) throws -> Data {
    try Data(contentsOf: url, options: [.mappedIfSafe])
  }
}

public struct BookTextService: BookTextServing {
  public static let maximumFamilyBlockBytes = 65_536

  private let locator: any BookSourceLocating
  private let reader: any BookDataReading
  private let now: @Sendable () -> Date

  public init(
    locator: any BookSourceLocating = DocumentsBookSourceLocator(),
    reader: any BookDataReading = FoundationBookDataReader(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.locator = locator
    self.reader = reader
    self.now = now
  }

  public func loadSource() async throws -> SourceRevision {
    try loadSnapshot().sourceRevision
  }

  public func getFamilyText(
    familyId: String,
    expectedSourceSHA256: String? = nil
  ) async throws -> FamilyTextRecord {
    let snapshot = try loadSnapshot()
    if let expectedSourceSHA256,
      expectedSourceSHA256.lowercased() != snapshot.sourceRevision.sha256
    {
      throw BookTextError.sourceChanged(
        expected: expectedSourceSHA256,
        actual: snapshot.sourceRevision.sha256
      )
    }

    return try snapshot.familyText(
      familyId: familyId,
      maximumBytes: Self.maximumFamilyBlockBytes
    )
  }

  public func loadSnapshot() throws -> BookTextSnapshot {
    let source = try locator.locateSource()
    guard source.url.isFileURL else {
      throw BookTextError.sourceUnreadable("The source URL is not a local file.")
    }

    let data: Data
    do {
      data = try reader.readData(from: source.url)
    } catch let error as BookTextError {
      throw error
    } catch {
      throw BookTextError.sourceUnreadable("The file data could not be read.")
    }

    return try BookTextSnapshot(
      data: data,
      fileName: source.url.lastPathComponent,
      sourceId: source.sourceId,
      loadedAt: now()
    )
  }
}

public struct BookTextSnapshot: Sendable {
  public let completeText: String
  public let sourceRevision: SourceRevision

  private let lines: [SourceLine]
  private let headers: [FamilyHeader]

  public init(
    data: Data,
    fileName: String,
    sourceId: String,
    loadedAt: Date = Date()
  ) throws {
    guard fileName == canonicalRootsFileName else {
      throw BookTextError.sourceUnreadable(
        "Expected \(canonicalRootsFileName), found \(fileName)."
      )
    }
    guard let completeText = String(data: data, encoding: .utf8) else {
      throw BookTextError.sourceUnreadable("The source is not valid UTF-8.")
    }

    let lines = Self.indexLines(in: completeText)
    guard let firstLine = lines.first else {
      throw BookTextError.sourceUnreadable("The source is empty.")
    }
    let marker = String(completeText[firstLine.contentRange])
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard marker == "canonical" else {
      throw BookTextError.sourceUnreadable(
        "The first line must contain the canonical marker."
      )
    }

    let hash = Self.sha256(data)
    self.completeText = completeText
    self.sourceRevision = SourceRevision(
      sourceId: sourceId,
      fileName: canonicalRootsFileName,
      sha256: hash,
      byteCount: data.count,
      loadedAt: Self.rfc3339(loadedAt),
      canonicalMarkerValid: true
    )
    self.lines = lines
    self.headers = lines.enumerated().compactMap { index, line in
      Self.parseHeader(
        String(completeText[line.contentRange]),
        lineIndex: index
      )
    }
  }

  public func familyText(
    familyId: String,
    maximumBytes: Int = BookTextService.maximumFamilyBlockBytes
  ) throws -> FamilyTextRecord {
    let normalizedRequestedId = try Self.normalizedIdentifier(familyId)
    let matchingHeaders = headers.filter {
      $0.normalizedIdentifier == normalizedRequestedId
    }

    guard let header = matchingHeaders.first else {
      throw BookTextError.familyNotFound(normalizedRequestedId.uppercased())
    }
    guard matchingHeaders.count == 1 else {
      throw BookTextError.sourceUnreadable(
        "Family \(header.sourceIdentifier) occurs more than once."
      )
    }

    let nextHeaderLineIndex =
      headers.first(where: {
        $0.lineIndex > header.lineIndex
      })?.lineIndex ?? lines.count

    var finalLineIndex = nextHeaderLineIndex - 1
    while finalLineIndex > header.lineIndex {
      let candidate = String(completeText[lines[finalLineIndex].contentRange])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if candidate.isEmpty || candidate == "#" {
        finalLineIndex -= 1
      } else {
        break
      }
    }

    let rawRange =
      lines[header.lineIndex].fullRange.lowerBound..<lines[finalLineIndex].fullRange.upperBound
    let rawText = String(completeText[rawRange])
    let rawData = Data(rawText.utf8)
    guard rawData.count <= maximumBytes else {
      throw BookTextError.resourceLimitExceeded(
        actualBytes: rawData.count,
        limitBytes: maximumBytes
      )
    }

    let span = SourceSpan(
      sourceId: sourceRevision.sourceId,
      sourceSha256: sourceRevision.sha256,
      familyId: header.sourceIdentifier,
      pageReferences: header.pageReferences,
      startLine: lines[header.lineIndex].number,
      endLine: lines[finalLineIndex].number,
      blockSha256: Self.sha256(rawData)
    )
    return FamilyTextRecord(
      familyId: header.sourceIdentifier,
      rawText: rawText,
      source: sourceRevision,
      span: span
    )
  }

  public func containsFamily(_ familyId: String) -> Bool {
    guard let normalized = try? Self.normalizedIdentifier(familyId) else {
      return false
    }
    return headers.contains { $0.normalizedIdentifier == normalized }
  }

  private struct SourceLine: Sendable {
    let number: Int
    let contentRange: Range<String.Index>
    let fullRange: Range<String.Index>
  }

  private struct FamilyHeader: Sendable {
    let sourceIdentifier: String
    let normalizedIdentifier: String
    let pageReferences: [String]
    let lineIndex: Int
  }

  private static func indexLines(in text: String) -> [SourceLine] {
    guard !text.isEmpty else { return [] }

    var result: [SourceLine] = []
    var lineStart = text.startIndex
    var lineNumber = 1

    while lineStart < text.endIndex {
      let newline = text.unicodeScalars[lineStart...].firstIndex(of: "\n")
      let fullEnd = newline.map { text.index(after: $0) } ?? text.endIndex
      var contentEnd = newline ?? text.endIndex
      if contentEnd > lineStart {
        let previous = text.index(before: contentEnd)
        if text[previous] == "\r" {
          contentEnd = previous
        }
      }

      result.append(
        SourceLine(
          number: lineNumber,
          contentRange: lineStart..<contentEnd,
          fullRange: lineStart..<fullEnd
        ))
      lineStart = fullEnd
      lineNumber += 1
    }

    return result
  }

  private static func parseHeader(
    _ line: String,
    lineIndex: Int
  ) -> FamilyHeader? {
    let pattern = #"^\s*(.+?),\s+pages?\s+(.+?)\s*$"#
    guard
      let expression = try? NSRegularExpression(
        pattern: pattern,
        options: [.caseInsensitive]
      )
    else {
      return nil
    }

    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    guard let match = expression.firstMatch(in: line, range: range),
      match.range.location != NSNotFound,
      let identifierRange = Range(match.range(at: 1), in: line),
      let pagesRange = Range(match.range(at: 2), in: line)
    else {
      return nil
    }

    let sourceIdentifier = String(line[identifierRange])
      .trimmingCharacters(in: .whitespaces)
    guard let normalizedIdentifier = try? normalizedIdentifier(sourceIdentifier) else {
      return nil
    }
    let pageReferences = line[pagesRange]
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !pageReferences.isEmpty else { return nil }

    return FamilyHeader(
      sourceIdentifier: sourceIdentifier,
      normalizedIdentifier: normalizedIdentifier,
      pageReferences: pageReferences,
      lineIndex: lineIndex
    )
  }

  private static func normalizedIdentifier(_ familyId: String) throws -> String {
    let collapsed =
      familyId
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
    let pieces = collapsed.split(separator: " ")
    guard pieces.count >= 2,
      let finalPiece = pieces.last,
      validNumberSuffix(finalPiece),
      pieces.dropLast().allSatisfy(validNamePiece)
    else {
      throw BookTextError.invalidFamilyIdentifier(familyId)
    }
    return collapsed.lowercased()
  }

  private static func validNumberSuffix(_ value: Substring) -> Bool {
    guard let first = value.first, first.isNumber else { return false }
    let characters = Array(value)
    let digitCount = characters.prefix(while: { $0.isNumber }).count
    guard digitCount > 0 else { return false }
    let suffix = characters.dropFirst(digitCount)
    return suffix.isEmpty || (suffix.count == 1 && suffix.first?.isLetter == true)
  }

  private static func validNamePiece(_ value: Substring) -> Bool {
    !value.isEmpty
      && value.allSatisfy {
        $0.isLetter || $0 == "-" || $0 == "." || $0 == "/"
      }
  }

  private static func sha256(_ data: Data) -> String {
    sha256Hex(data)
  }

  private static func rfc3339(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

private func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
