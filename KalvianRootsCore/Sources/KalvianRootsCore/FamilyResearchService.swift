import CryptoKit
import Foundation

public struct PersonCandidateInput: Codable, Equatable, Sendable {
  public let source: PersonCandidate.SourceType
  public let rawName: String
  public let rawBirthDate: String?
  public let rawDeathDate: String?
  public let familySearchId: String?
  public let provenance: [SourceSpan]

  public init(
    source: PersonCandidate.SourceType,
    rawName: String,
    rawBirthDate: String? = nil,
    rawDeathDate: String? = nil,
    familySearchId: String? = nil,
    provenance: [SourceSpan] = []
  ) {
    self.source = source
    self.rawName = rawName
    self.rawBirthDate = rawBirthDate
    self.rawDeathDate = rawDeathDate
    self.familySearchId = familySearchId
    self.provenance = provenance
  }
}

public struct StoredHiskiEvidence: Codable, Equatable, Sendable {
  public let candidateId: String
  public let query: HiskiQuery
  public let candidate: HiskiResultCandidate
  public let searchResponseSha256: String
  public let searchCandidateCount: Int
  public let searchWasAmbiguous: Bool
  public let searchRetrievedAt: String
  public let record: HiskiRecord?
  public let recordRetrievedAt: String?

  public init(
    candidateId: String,
    query: HiskiQuery,
    candidate: HiskiResultCandidate,
    searchResponseSha256: String,
    searchCandidateCount: Int,
    searchWasAmbiguous: Bool,
    searchRetrievedAt: String,
    record: HiskiRecord? = nil,
    recordRetrievedAt: String? = nil
  ) {
    self.candidateId = candidateId
    self.query = query
    self.candidate = candidate
    self.searchResponseSha256 = searchResponseSha256
    self.searchCandidateCount = searchCandidateCount
    self.searchWasAmbiguous = searchWasAmbiguous
    self.searchRetrievedAt = searchRetrievedAt
    self.record = record
    self.recordRetrievedAt = recordRetrievedAt
  }
}

public enum ResearchStoreError: Error, Equatable, Sendable {
  case unavailable(String)
  case recordNotFound(String)
  case invalidRequest(String)

  public var code: String {
    switch self {
    case .unavailable: "cache_unavailable"
    case .recordNotFound: "record_not_found"
    case .invalidRequest: "invalid_request"
    }
  }
}

extension ResearchStoreError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unavailable(let reason): "The research store is unavailable: \(reason)"
    case .recordNotFound(let id): "No research record is stored for \(id)."
    case .invalidRequest(let reason): "The research request is invalid: \(reason)"
    }
  }
}

public protocol HiskiEvidenceStoring: Sendable {
  func store(searchResult: HiskiSearchResult, retrievedAt: String) async throws
  func store(record: HiskiRecord, retrievedAt: String) async throws
  func evidence(candidateId: String) async throws -> StoredHiskiEvidence?
  func evidence(candidateIds: [String]) async throws -> [StoredHiskiEvidence]
}

public actor MemoryHiskiEvidenceStore: HiskiEvidenceStoring {
  private var records: [String: StoredHiskiEvidence]

  public init(evidence: [StoredHiskiEvidence] = []) {
    records = Dictionary(uniqueKeysWithValues: evidence.map { ($0.candidateId, $0) })
  }

  public func store(searchResult: HiskiSearchResult, retrievedAt: String) {
    for candidate in searchResult.candidates {
      let prior = records[candidate.candidateId]
      records[candidate.candidateId] = StoredHiskiEvidence(
        candidateId: candidate.candidateId,
        query: searchResult.query,
        candidate: candidate,
        searchResponseSha256: searchResult.responseSha256,
        searchCandidateCount: searchResult.candidateCount,
        searchWasAmbiguous: searchResult.ambiguous,
        searchRetrievedAt: retrievedAt,
        record: prior?.record,
        recordRetrievedAt: prior?.recordRetrievedAt
      )
    }
  }

  public func store(record: HiskiRecord, retrievedAt: String) {
    let prior = records[record.candidate.candidateId]
    records[record.candidate.candidateId] = StoredHiskiEvidence(
      candidateId: record.candidate.candidateId,
      query: record.query,
      candidate: record.candidate,
      searchResponseSha256: prior?.searchResponseSha256 ?? record.responseSha256,
      searchCandidateCount: prior?.searchCandidateCount ?? 1,
      searchWasAmbiguous: prior?.searchWasAmbiguous ?? false,
      searchRetrievedAt: prior?.searchRetrievedAt ?? retrievedAt,
      record: record,
      recordRetrievedAt: retrievedAt
    )
  }

  public func evidence(candidateId: String) -> StoredHiskiEvidence? { records[candidateId] }

  public func evidence(candidateIds: [String]) -> [StoredHiskiEvidence] {
    candidateIds.compactMap { records[$0] }
  }
}

public actor FileHiskiEvidenceStore: HiskiEvidenceStoring {
  private struct Payload: Codable {
    let schemaVersion: Int
    var records: [String: StoredHiskiEvidence]
  }

  private let url: URL
  private let fileManager: FileManager
  private var loaded: Payload?

  public init(url: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.url = url ?? Self.defaultURL(fileManager: fileManager)
  }

  public func store(searchResult: HiskiSearchResult, retrievedAt: String) throws {
    var payload = try load()
    for candidate in searchResult.candidates {
      let prior = payload.records[candidate.candidateId]
      payload.records[candidate.candidateId] = StoredHiskiEvidence(
        candidateId: candidate.candidateId, query: searchResult.query, candidate: candidate,
        searchResponseSha256: searchResult.responseSha256,
        searchCandidateCount: searchResult.candidateCount,
        searchWasAmbiguous: searchResult.ambiguous, searchRetrievedAt: retrievedAt,
        record: prior?.record, recordRetrievedAt: prior?.recordRetrievedAt)
    }
    try save(payload)
  }

  public func store(record: HiskiRecord, retrievedAt: String) throws {
    var payload = try load()
    let prior = payload.records[record.candidate.candidateId]
    payload.records[record.candidate.candidateId] = StoredHiskiEvidence(
      candidateId: record.candidate.candidateId, query: record.query,
      candidate: record.candidate,
      searchResponseSha256: prior?.searchResponseSha256 ?? record.responseSha256,
      searchCandidateCount: prior?.searchCandidateCount ?? 1,
      searchWasAmbiguous: prior?.searchWasAmbiguous ?? false,
      searchRetrievedAt: prior?.searchRetrievedAt ?? retrievedAt,
      record: record, recordRetrievedAt: retrievedAt)
    try save(payload)
  }

  public func evidence(candidateId: String) throws -> StoredHiskiEvidence? {
    try load().records[candidateId]
  }

  public func evidence(candidateIds: [String]) throws -> [StoredHiskiEvidence] {
    let payload = try load()
    return candidateIds.compactMap { payload.records[$0] }
  }

  private func load() throws -> Payload {
    if let loaded { return loaded }
    guard fileManager.fileExists(atPath: url.path) else {
      let empty = Payload(schemaVersion: 1, records: [:])
      loaded = empty
      return empty
    }
    do {
      let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
      guard payload.schemaVersion == 1 else {
        throw ResearchStoreError.unavailable("unsupported HiSki evidence schema")
      }
      loaded = payload
      return payload
    } catch let error as ResearchStoreError {
      throw error
    } catch {
      throw ResearchStoreError.unavailable(error.localizedDescription)
    }
  }

  private func save(_ payload: Payload) throws {
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(payload).write(to: url, options: [.atomic])
      loaded = payload
    } catch {
      throw ResearchStoreError.unavailable(error.localizedDescription)
    }
  }

  private static func defaultURL(fileManager: FileManager) -> URL {
    guard
      let support = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else { fatalError("Application Support directory is unavailable") }
    return support.appendingPathComponent("Kalvian Roots", isDirectory: true)
      .appendingPathComponent("Research", isDirectory: true)
      .appendingPathComponent("hiski-evidence.json")
  }
}

public struct ComparedPersonCandidate: Codable, Equatable, Sendable {
  public let source: PersonCandidate.SourceType
  public let rawName: String
  public let rawBirthDate: String?
  public let rawDeathDate: String?
  public let canonicalName: String
  public let normalizedBirthDate: String?
  public let familySearchId: String?
  public let hiskiCandidateId: String?
  public let hiskiCitationURL: String?
  public let provenance: [SourceSpan]

  init(_ candidate: PersonCandidate) {
    source = candidate.source
    rawName = candidate.rawName
    rawBirthDate = candidate.rawBirthDate
    rawDeathDate = candidate.rawDeathDate
    canonicalName = candidate.identity.canonicalName
    normalizedBirthDate = GenealogyDateParser.normalized(candidate.birthDate)
    familySearchId = candidate.familySearchId
    hiskiCandidateId = candidate.hiskiCandidateId
    hiskiCitationURL = candidate.hiskiCitation?.absoluteString
    provenance = candidate.provenance
  }
}

public struct FamilyComparisonRowRecord: Codable, Equatable, Sendable {
  public let canonicalName: String
  public let normalizedBirthDate: String?
  public let status: String
  public let familySearch: ComparedPersonCandidate?
  public let juuret: ComparedPersonCandidate?
  public let hiski: ComparedPersonCandidate?

  init(_ match: FamilyComparisonResult.Match) {
    canonicalName = match.identity.canonicalName
    normalizedBirthDate = GenealogyDateParser.normalized(match.identity.birthDate)
    familySearch = match.familySearch.map(ComparedPersonCandidate.init)
    juuret = match.juuretKalvialla.map(ComparedPersonCandidate.init)
    hiski = match.hiski.map(ComparedPersonCandidate.init)
    status = Self.status(match)
  }

  private static func status(_ match: FamilyComparisonResult.Match) -> String {
    switch (match.juuretKalvialla, match.hiski, match.familySearch) {
    case (.some, .some, .some): "present_in_all_three"
    case (.some, .some, nil): "missing_in_familysearch"
    case (.some, nil, nil): "juuret_only"
    case (nil, .some, nil): "hiski_only"
    case (nil, nil, .some(let familySearch)):
      familySearch.birthDate == nil ? "familysearch_date_needed" : "familysearch_only"
    case (.some, nil, .some): "missing_in_hiski"
    case (nil, .some, .some): "missing_in_juuret"
    case (nil, nil, nil): "unknown"
    }
  }
}

public struct FamilyComparisonRecord: Codable, Equatable, Sendable {
  public let comparisonId: String
  public let contextId: String
  public let selectedPerson: PersonReference
  public let startingFamilyId: String
  public let accessedFamilyIds: [String]
  public let rows: [FamilyComparisonRowRecord]
  public let matchCount: Int
  public let familySearchOnlyCount: Int
  public let juuretOnlyCount: Int
  public let hiskiOnlyCount: Int
  public let familySearchCandidateCount: Int
  public let hiskiEvidenceIds: [String]
  public let conflicts: [FactConflict]
  public let warnings: [NetworkWarning]
  public let provenance: [SourceSpan]

  public init(
    comparisonId: String, contextId: String, selectedPerson: PersonReference,
    startingFamilyId: String, accessedFamilyIds: [String],
    rows: [FamilyComparisonRowRecord], matchCount: Int,
    familySearchOnlyCount: Int, juuretOnlyCount: Int, hiskiOnlyCount: Int,
    familySearchCandidateCount: Int, hiskiEvidenceIds: [String],
    conflicts: [FactConflict], warnings: [NetworkWarning], provenance: [SourceSpan]
  ) {
    self.comparisonId = comparisonId
    self.contextId = contextId
    self.selectedPerson = selectedPerson
    self.startingFamilyId = startingFamilyId
    self.accessedFamilyIds = accessedFamilyIds
    self.rows = rows
    self.matchCount = matchCount
    self.familySearchOnlyCount = familySearchOnlyCount
    self.juuretOnlyCount = juuretOnlyCount
    self.hiskiOnlyCount = hiskiOnlyCount
    self.familySearchCandidateCount = familySearchCandidateCount
    self.hiskiEvidenceIds = hiskiEvidenceIds
    self.conflicts = conflicts
    self.warnings = warnings
    self.provenance = provenance
  }
}

public protocol FamilyComparisonStoring: Sendable {
  func store(_ record: FamilyComparisonRecord) async throws
  func comparison(id: String) async throws -> FamilyComparisonRecord?
}

public actor MemoryFamilyComparisonStore: FamilyComparisonStoring {
  private var records: [String: FamilyComparisonRecord]

  public init(records: [FamilyComparisonRecord] = []) {
    self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.comparisonId, $0) })
  }

  public func store(_ record: FamilyComparisonRecord) { records[record.comparisonId] = record }
  public func comparison(id: String) -> FamilyComparisonRecord? { records[id] }
}

public actor FileFamilyComparisonStore: FamilyComparisonStoring {
  private struct Payload: Codable {
    let schemaVersion: Int
    var records: [String: FamilyComparisonRecord]
  }

  private let url: URL
  private let fileManager: FileManager
  private var loaded: Payload?

  public init(url: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.url = url ?? Self.defaultURL(fileManager: fileManager)
  }

  public func store(_ record: FamilyComparisonRecord) throws {
    var payload = try load()
    payload.records[record.comparisonId] = record
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(payload).write(to: url, options: [.atomic])
      loaded = payload
    } catch {
      throw ResearchStoreError.unavailable(error.localizedDescription)
    }
  }

  public func comparison(id: String) throws -> FamilyComparisonRecord? {
    try load().records[id]
  }

  private func load() throws -> Payload {
    if let loaded { return loaded }
    guard fileManager.fileExists(atPath: url.path) else {
      let empty = Payload(schemaVersion: 1, records: [:])
      loaded = empty
      return empty
    }
    do {
      let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
      guard payload.schemaVersion == 1 else {
        throw ResearchStoreError.unavailable("unsupported comparison schema")
      }
      loaded = payload
      return payload
    } catch let error as ResearchStoreError {
      throw error
    } catch {
      throw ResearchStoreError.unavailable(error.localizedDescription)
    }
  }

  private static func defaultURL(fileManager: FileManager) -> URL {
    guard
      let support = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else { fatalError("Application Support directory is unavailable") }
    return support.appendingPathComponent("Kalvian Roots", isDirectory: true)
      .appendingPathComponent("Research", isDirectory: true)
      .appendingPathComponent("family-comparisons.json")
  }
}

public struct HumanResearchDecision: Codable, Equatable, Sendable {
  public let code: String
  public let message: String
  public let relatedProposalId: String?

  public init(code: String, message: String, relatedProposalId: String? = nil) {
    self.code = code
    self.message = message
    self.relatedProposalId = relatedProposalId
  }
}

public struct FamilyResearchWorkup: Codable, Equatable, Sendable {
  public let workupId: String
  public let startingFamilyId: String
  public let selectedPerson: PersonReference
  public let accessedFamilyIds: [String]
  public let parsedFamilies: [ParsedFamilyRecord]
  public let claims: [FactClaim]
  public let comparison: FamilyComparisonRecord
  public let juuretCitationProposal: CitationProposal
  public let hiskiCitationProposals: [CitationProposal]
  public let hiskiEvidence: [StoredHiskiEvidence]
  public let conflicts: [FactConflict]
  public let warnings: [NetworkWarning]
  public let humanDecisionsRequired: [HumanResearchDecision]
  public let renderedReport: String
  public let requiresApproval: Bool

  public init(
    workupId: String, startingFamilyId: String, selectedPerson: PersonReference,
    accessedFamilyIds: [String], parsedFamilies: [ParsedFamilyRecord], claims: [FactClaim],
    comparison: FamilyComparisonRecord, juuretCitationProposal: CitationProposal,
    hiskiCitationProposals: [CitationProposal], hiskiEvidence: [StoredHiskiEvidence],
    conflicts: [FactConflict], warnings: [NetworkWarning],
    humanDecisionsRequired: [HumanResearchDecision], renderedReport: String
  ) {
    self.workupId = workupId
    self.startingFamilyId = startingFamilyId
    self.selectedPerson = selectedPerson
    self.accessedFamilyIds = accessedFamilyIds
    self.parsedFamilies = parsedFamilies
    self.claims = claims
    self.comparison = comparison
    self.juuretCitationProposal = juuretCitationProposal
    self.hiskiCitationProposals = hiskiCitationProposals
    self.hiskiEvidence = hiskiEvidence
    self.conflicts = conflicts
    self.warnings = warnings
    self.humanDecisionsRequired = humanDecisionsRequired
    self.renderedReport = renderedReport
    requiresApproval = true
  }
}

public struct FamilyResearchService: Sendable {
  private let nameManager: BuiltinNameEquivalenceManager

  public init(nameManager: BuiltinNameEquivalenceManager = BuiltinNameEquivalenceManager()) {
    self.nameManager = nameManager
  }

  public func compare(
    context: PersonContextResolution,
    familySearchCandidates: [PersonCandidateInput],
    hiskiEvidence: [StoredHiskiEvidence]
  ) throws -> FamilyComparisonRecord {
    guard
      let starting = context.families.first(where: {
        Self.familyKey($0.parsedFamily.familyId) == Self.familyKey(context.selectedPerson.familyId)
      })
    else {
      throw ResearchStoreError.invalidRequest(
        "the selected person's starting family is absent from the resolved context")
    }
    guard familySearchCandidates.allSatisfy({ $0.source == .familySearch }) else {
      throw ResearchStoreError.invalidRequest(
        "familySearchCandidates may contain only FamilySearch source records")
    }

    let juuret = starting.parsedFamily.couples.flatMap(\.children).map { person in
      PersonCandidate(
        name: person.name, birthDate: GenealogyDateParser.parse(person.birthDate),
        deathDate: GenealogyDateParser.parse(person.deathDate),
        rawBirthDate: person.birthDate, rawDeathDate: person.deathDate,
        source: .juuretKalvialla, nameManager: nameManager,
        familySearchId: person.familySearchId, provenance: [starting.span])
    }
    let familySearch = familySearchCandidates.map { input in
      PersonCandidate(
        name: input.rawName, identityName: Self.givenName(input.rawName),
        birthDate: GenealogyDateParser.parse(input.rawBirthDate),
        deathDate: GenealogyDateParser.parse(input.rawDeathDate),
        rawBirthDate: input.rawBirthDate, rawDeathDate: input.rawDeathDate,
        source: input.source, nameManager: nameManager,
        familySearchId: input.familySearchId, provenance: input.provenance)
    }
    let hiski = hiskiEvidence.compactMap { evidence -> PersonCandidate? in
      guard evidence.candidate.eventType == .birth,
        let rawName = Self.field("Child", in: evidence.candidate),
        let rawBirthDate = Self.field("Born", in: evidence.candidate)
      else { return nil }
      return PersonCandidate(
        name: rawName, birthDate: GenealogyDateParser.parse(rawBirthDate),
        rawBirthDate: rawBirthDate, source: .hiski, nameManager: nameManager,
        hiskiCitation: evidence.record.flatMap { URL(string: $0.citationURL) },
        hiskiCandidateId: evidence.candidateId,
        provenance: [evidence.query.motivation.sourceSpan])
    }
    let result = FamilyComparisonResult(
      familySearch: familySearch, juuretKalvialla: juuret, hiski: hiski)
    var warnings = context.missingReferences
    if !context.complete {
      warnings.append(
        NetworkWarning(
          code: "incomplete_context",
          message:
            "The family context is incomplete; the comparison is bounded to returned evidence."))
    }
    if familySearchCandidates.isEmpty {
      warnings.append(
        NetworkWarning(
          code: "familysearch_not_supplied",
          message: "No UI-extracted FamilySearch candidates were supplied."))
    }
    for input in familySearchCandidates where GenealogyDateParser.parse(input.rawBirthDate) == nil {
      warnings.append(
        NetworkWarning(
          code: "familysearch_birth_date_missing",
          message:
            "\(input.rawName) has no parseable FamilySearch birth date and was not identity-matched."
        ))
    }
    for evidence in hiskiEvidence where evidence.searchWasAmbiguous {
      warnings.append(
        NetworkWarning(
          code: "ambiguous_hiski_candidates",
          message:
            "HiSki query \(evidence.query.queryId) returned multiple candidates; identity requires review."
        ))
    }
    warnings = Self.uniqueWarnings(warnings)
    let evidenceIds = hiskiEvidence.map(\.candidateId)
    let comparisonId = Self.stableID(
      "family-comparison", context.contextId,
      familySearchCandidates.map {
        "\($0.rawName)|\($0.rawBirthDate ?? "")|\($0.familySearchId ?? "")"
      }
      .joined(separator: ";"),
      evidenceIds.joined(separator: ";"))
    return FamilyComparisonRecord(
      comparisonId: comparisonId, contextId: context.contextId,
      selectedPerson: context.selectedPerson, startingFamilyId: starting.parsedFamily.familyId,
      accessedFamilyIds: context.families.map { $0.parsedFamily.familyId },
      rows: result.rows.map(FamilyComparisonRowRecord.init),
      matchCount: result.matches.count,
      familySearchOnlyCount: result.familySearchOnly.count,
      juuretOnlyCount: result.juuretOnly.count, hiskiOnlyCount: result.hiskiOnly.count,
      familySearchCandidateCount: familySearchCandidates.count,
      hiskiEvidenceIds: evidenceIds, conflicts: context.conflicts,
      warnings: warnings, provenance: Self.uniqueSpans(context.families.map(\.span)))
  }

  public func prepareWorkup(
    comparison: FamilyComparisonRecord,
    context: PersonContextResolution,
    juuretProposal: CitationProposal,
    hiskiEvidence: [StoredHiskiEvidence]
  ) throws -> FamilyResearchWorkup {
    guard comparison.contextId == context.contextId,
      comparison.selectedPerson == context.selectedPerson,
      juuretProposal.selectedPerson == context.selectedPerson
    else {
      throw ResearchStoreError.invalidRequest(
        "comparison, context, and selected person do not identify the same workup")
    }
    let relevantEvidence = hiskiEvidence.filter {
      $0.query.motivation.person == context.selectedPerson
    }
    let hiskiProposals = relevantEvidence.compactMap { evidence -> CitationProposal? in
      guard let record = evidence.record else { return nil }
      var warnings: [NetworkWarning] = []
      if evidence.searchWasAmbiguous {
        warnings.append(
          NetworkWarning(
            code: "ambiguous_hiski_candidates",
            message:
              "This detail record came from an ambiguous result set and still requires identity review."
          ))
      }
      let rendered = record.citationURL
      return CitationProposal(
        proposalId: Self.stableID("hiski-citation", context.contextId, evidence.candidateId),
        citationType: "hiski_\(evidence.candidate.eventType.rawValue)",
        selectedPerson: context.selectedPerson, renderedText: rendered,
        sourceSpans: [record.query.motivation.sourceSpan], conflicts: context.conflicts,
        warnings: warnings, sourceURL: record.citationURL,
        hiskiQueryId: record.query.queryId, hiskiCandidateId: evidence.candidateId)
    }
    var decisions = context.conflicts.map {
      HumanResearchDecision(
        code: "resolve_conflict",
        message:
          "Review \($0.field) conflict: \($0.claims.map(\.value).joined(separator: " versus ")).")
    }
    if comparison.familySearchCandidateCount == 0 {
      decisions.append(
        HumanResearchDecision(
          code: "familysearch_review_needed",
          message:
            "Use the visible FamilySearch workflow to check the selected person and its sourced dates."
        ))
    }
    for evidence in relevantEvidence where evidence.searchWasAmbiguous {
      decisions.append(
        HumanResearchDecision(
          code: "choose_hiski_identity",
          message: "Confirm whether HiSki candidate \(evidence.candidateId) is the selected person."
        ))
    }
    for evidence in relevantEvidence where evidence.record == nil {
      decisions.append(
        HumanResearchDecision(
          code: "retrieve_hiski_record",
          message:
            "Review and retrieve the detail record for HiSki candidate \(evidence.candidateId)."))
    }
    let allProposals = [juuretProposal] + hiskiProposals
    decisions += allProposals.map {
      HumanResearchDecision(
        code: "approve_citation",
        message: "Approve or reject \($0.citationType) proposal \($0.proposalId).",
        relatedProposalId: $0.proposalId)
    }
    let warnings = Self.uniqueWarnings(
      comparison.warnings + juuretProposal.warnings + hiskiProposals.flatMap(\.warnings))
    let workupId = Self.stableID(
      "family-workup", comparison.comparisonId,
      allProposals.map(\.proposalId).joined(separator: ";"))
    let report = Self.renderReport(
      workupId: workupId, comparison: comparison, context: context,
      juuretProposal: juuretProposal, hiskiProposals: hiskiProposals,
      evidence: relevantEvidence, decisions: decisions)
    return FamilyResearchWorkup(
      workupId: workupId, startingFamilyId: comparison.startingFamilyId,
      selectedPerson: context.selectedPerson,
      accessedFamilyIds: comparison.accessedFamilyIds,
      parsedFamilies: context.families, claims: context.claims,
      comparison: comparison, juuretCitationProposal: juuretProposal,
      hiskiCitationProposals: hiskiProposals, hiskiEvidence: relevantEvidence,
      conflicts: context.conflicts, warnings: warnings,
      humanDecisionsRequired: decisions, renderedReport: report)
  }

  private static func renderReport(
    workupId: String, comparison: FamilyComparisonRecord, context: PersonContextResolution,
    juuretProposal: CitationProposal, hiskiProposals: [CitationProposal],
    evidence: [StoredHiskiEvidence], decisions: [HumanResearchDecision]
  ) -> String {
    var lines = [
      "Kalvian Roots family workup \(workupId)",
      "Starting family: \(comparison.startingFamilyId)",
      "Selected person: \(context.selectedPerson.rawName) (\(context.selectedPerson.rawBirthDate ?? "birth date unknown"))",
      "Accessed families: \(comparison.accessedFamilyIds.joined(separator: ", "))",
      "Parsed families: \(context.families.map { "\($0.parsedFamily.familyId) pages \($0.parsedFamily.pageReferences.joined(separator: ", "))" }.joined(separator: "; "))",
      "Claims: \(context.claims.count); conflicts: \(context.conflicts.count)",
      "Comparison rows: \(comparison.rows.count); matches: \(comparison.matchCount)",
      "",
      "Juuret citation proposal:",
      juuretProposal.renderedText,
      "",
      "HiSki citation proposals:",
    ]
    if hiskiProposals.isEmpty {
      lines.append("(none; \(evidence.count) candidate evidence record(s) retained for review)")
    } else {
      for proposal in hiskiProposals {
        lines.append("[\(proposal.citationType)] \(proposal.renderedText)")
      }
    }
    lines += ["", "Human decisions required:"]
    lines += decisions.isEmpty ? ["(none)"] : decisions.map { "- \($0.message)" }
    lines += ["", "No FamilySearch change or canonical Juuret source change was performed."]
    return lines.joined(separator: "\n")
  }

  private static func field(_ label: String, in candidate: HiskiResultCandidate) -> String? {
    candidate.fields.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }?.value
  }

  private static func givenName(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? value
  }

  private static func uniqueWarnings(_ warnings: [NetworkWarning]) -> [NetworkWarning] {
    var seen: Set<String> = []
    return warnings.filter { seen.insert("\($0.code)|\($0.message)").inserted }
  }

  private static func uniqueSpans(_ spans: [SourceSpan]) -> [SourceSpan] {
    var seen: Set<String> = []
    return spans.filter { seen.insert("\($0.sourceSha256)|\($0.blockSha256)").inserted }
  }

  private static func familyKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  private static func stableID(_ parts: String...) -> String {
    let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
