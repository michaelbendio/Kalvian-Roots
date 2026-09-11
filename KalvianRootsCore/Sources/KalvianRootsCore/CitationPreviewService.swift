import Foundation

public struct CitationPreview: Codable, Sendable {
  public let context: PersonContextResolution
  public let proposal: CitationProposal
}

/// Composes the existing resolver and renderer without saving a context, importing legacy
/// desktop entries, contacting AI, or creating an approval/review record.
public struct CitationPreviewService: Sendable {
  private let book: any BookTextServing
  private let parser: ReadOnlyParsingService
  private let citation: any CitationServing

  public init(
    book: any BookTextServing, parser: any FamilyParsingServing,
    citation: any CitationServing = JuuretCitationService()
  ) {
    self.book = book
    self.parser = ReadOnlyParsingService(base: parser)
    self.citation = citation
  }

  public func preview(
    person: PersonReference, limits: TraversalLimits,
    expectedSourceSHA256: String
  ) async throws -> CitationPreview {
    guard limits.isValid else { throw FamilyNetworkError.invalidLimits }
    let source = try await book.getFamilyText(
      familyId: person.familyId, expectedSourceSHA256: expectedSourceSHA256)
    let starting = try await parser.parseFamily(source: source, cachePolicy: .cacheOnly)
    let context = try await FamilyNetworkService(bookTextService: book, parsingService: parser)
      .resolvePersonContext(person: person, startingFamily: starting, limits: limits)
    let proposal = try citation.generateJuuretCitation(context: context, selectedPerson: person)
    guard try await book.loadSource().sha256 == source.source.sha256 else {
      throw CacheMaintenanceError.changed
    }
    return CitationPreview(context: context, proposal: proposal)
  }
}

private struct ReadOnlyParsingService: FamilyParsingServing {
  let base: any FamilyParsingServing
  func getParsedFamily(familyId: String, sourceSHA256: String) async throws -> ParsedFamilyRecord? {
    try await base.getParsedFamily(familyId: familyId, sourceSHA256: sourceSHA256)
  }
  func parseFamily(source: FamilyTextRecord, cachePolicy: ParseCachePolicy) async throws
    -> ParsedFamilyRecord
  {
    guard
      let record = try await getParsedFamily(
        familyId: source.familyId, sourceSHA256: source.source.sha256)
    else { throw FamilyParsingError.cacheMiss(source.familyId) }
    try FamilyParsingService.validateCachedRecord(record, against: source, allowLegacy: true)
    if record.parserImplementationVersion == "legacy-schema2-unknown",
      !record.warnings.contains(where: { $0.code == "legacy_cache_provenance_limited" })
    {
      return ParsedFamilyRecord(
        familyId: record.familyId, source: record.source, span: record.span,
        parserImplementationVersion: record.parserImplementationVersion,
        parsedFamily: record.parsedFamily,
        warnings: record.warnings + [
          ParsingWarning(
            code: "legacy_cache_provenance_limited",
            message:
              "The imported desktop record does not retain its original AI response, source hash, or parser provenance."
          )
        ])
    }
    return record
  }
}
