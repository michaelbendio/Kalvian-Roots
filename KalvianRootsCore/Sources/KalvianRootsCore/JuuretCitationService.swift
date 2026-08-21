import CryptoKit
import Foundation

public struct CitationProposal: Codable, Equatable, Sendable {
  public let proposalId: String
  public let citationType: String
  public let selectedPerson: PersonReference
  public let renderedText: String
  public let sourceSpans: [SourceSpan]
  public let conflicts: [FactConflict]
  public let warnings: [NetworkWarning]
  public let sourceURL: String?
  public let hiskiQueryId: String?
  public let hiskiCandidateId: String?
  public let requiresApproval: Bool

  public init(
    proposalId: String,
    citationType: String = "juuret",
    selectedPerson: PersonReference,
    renderedText: String,
    sourceSpans: [SourceSpan],
    conflicts: [FactConflict],
    warnings: [NetworkWarning],
    sourceURL: String? = nil,
    hiskiQueryId: String? = nil,
    hiskiCandidateId: String? = nil
  ) {
    self.proposalId = proposalId
    self.citationType = citationType
    self.selectedPerson = selectedPerson
    self.renderedText = renderedText
    self.sourceSpans = sourceSpans
    self.conflicts = conflicts
    self.warnings = warnings
    self.sourceURL = sourceURL
    self.hiskiQueryId = hiskiQueryId
    self.hiskiCandidateId = hiskiCandidateId
    self.requiresApproval = true
  }
}

public enum CitationServiceError: Error, Equatable, Sendable {
  case contextNotFound(String)
  case selectedPersonMismatch
  case sourceFamilyMissing(String)
  case asChildCitationRequired(String)
  case invalidSelectedPerson(String)
  case contextStoreUnavailable(String)

  public var code: String {
    switch self {
    case .contextNotFound: "record_not_found"
    case .selectedPersonMismatch, .sourceFamilyMissing, .asChildCitationRequired,
      .invalidSelectedPerson:
      "invalid_request"
    case .contextStoreUnavailable: "cache_unavailable"
    }
  }
}

extension CitationServiceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .contextNotFound(let id):
      "No resolved person context is stored for \(id)."
    case .selectedPersonMismatch:
      "The selected person does not match the stored context."
    case .sourceFamilyMissing(let familyId):
      "The citation source family \(familyId) is absent from the resolved context."
    case .asChildCitationRequired(let familyId):
      "The required as_child citation family \(familyId) was not resolved."
    case .invalidSelectedPerson(let reason):
      "The selected person cannot be rendered: \(reason)"
    case .contextStoreUnavailable(let reason):
      "The resolved-context store is unavailable: \(reason)"
    }
  }
}

public protocol CitationServing: Sendable {
  func generateJuuretCitation(
    context: PersonContextResolution,
    selectedPerson: PersonReference
  ) throws -> CitationProposal
}

public protocol PersonContextStoring: Sendable {
  func store(_ context: PersonContextResolution) async throws
  func context(id: String) async throws -> PersonContextResolution?
}

public actor MemoryPersonContextStore: PersonContextStoring {
  private var contexts: [String: PersonContextResolution]

  public init(contexts: [PersonContextResolution] = []) {
    self.contexts = Dictionary(uniqueKeysWithValues: contexts.map { ($0.contextId, $0) })
  }

  public func store(_ context: PersonContextResolution) {
    contexts[context.contextId] = context
  }

  public func context(id: String) -> PersonContextResolution? {
    contexts[id]
  }
}

public actor FilePersonContextStore: PersonContextStoring {
  private struct Payload: Codable {
    let schemaVersion: Int
    var contexts: [String: PersonContextResolution]
  }

  private let url: URL
  private let fileManager: FileManager
  private var loaded: Payload?

  public init(url: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.url = url ?? Self.defaultURL(fileManager: fileManager)
  }

  public func store(_ context: PersonContextResolution) throws {
    var payload = try load()
    payload.contexts[context.contextId] = context
    let directory = url.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      try encoder.encode(payload).write(to: url, options: [.atomic])
      loaded = payload
    } catch {
      throw CitationServiceError.contextStoreUnavailable(error.localizedDescription)
    }
  }

  public func context(id: String) throws -> PersonContextResolution? {
    try load().contexts[id]
  }

  private func load() throws -> Payload {
    if let loaded { return loaded }
    guard fileManager.fileExists(atPath: url.path) else {
      let payload = Payload(schemaVersion: 1, contexts: [:])
      loaded = payload
      return payload
    }
    do {
      let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
      guard payload.schemaVersion == 1 else {
        throw CitationServiceError.contextStoreUnavailable(
          "Unsupported person-context cache schema \(payload.schemaVersion)."
        )
      }
      loaded = payload
      return payload
    } catch let error as CitationServiceError {
      throw error
    } catch {
      throw CitationServiceError.contextStoreUnavailable(error.localizedDescription)
    }
  }

  private static func defaultURL(fileManager: FileManager) -> URL {
    guard
      let support = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else {
      fatalError("Application Support directory is unavailable")
    }
    return support.appendingPathComponent("Kalvian Roots/Cache/person-contexts-v1.json")
  }
}

public struct JuuretCitationService: CitationServing, Sendable {
  public init() {}

  public func generateJuuretCitation(
    context: PersonContextResolution,
    selectedPerson: PersonReference
  ) throws -> CitationProposal {
    guard context.selectedPerson == selectedPerson else {
      throw CitationServiceError.selectedPersonMismatch
    }
    let renderingTarget = try citationTarget(in: context, selectedPerson: selectedPerson)
    guard
      let sourceRecord = context.families.first(where: {
        familyKey($0.familyId) == familyKey(renderingTarget.familyId)
      })
    else {
      throw CitationServiceError.sourceFamilyMissing(renderingTarget.familyId)
    }
    try validate(renderingTarget, in: sourceRecord.parsedFamily)

    let conflictedFields = Set(context.conflicts.map(\.field))
    var renderableClaims = context.claims.filter {
      $0.derivation != .referenceHarvested || !conflictedFields.contains($0.field)
    }
    if renderingTarget != selectedPerson {
      renderableClaims = renderableClaims.filter {
        $0.sourceSpan.blockSha256 == sourceRecord.span.blockSha256
      }
    }
    let rendered = try render(
      family: sourceRecord.parsedFamily,
      sourceSpan: sourceRecord.span,
      selectedPerson: renderingTarget,
      claims: renderableClaims
    )
    let spans = sourceSpans(
      startingWith: sourceRecord.span,
      claims: renderingTarget == selectedPerson ? context.claims : renderableClaims,
      conflicts: renderingTarget == selectedPerson ? context.conflicts : []
    )
    var warnings: [NetworkWarning] = []
    for warning in context.families.flatMap(\.warnings) {
      appendUnique(
        &warnings,
        NetworkWarning(code: warning.code, message: warning.message)
      )
    }
    for warning in context.missingReferences { appendUnique(&warnings, warning) }
    for cycle in context.cycles {
      appendUnique(
        &warnings,
        NetworkWarning(
          code: "cycle_detected",
          message: "Family-reference cycle: \(cycle.joined(separator: " -> "))"
        )
      )
    }
    if !context.complete {
      appendUnique(
        &warnings,
        NetworkWarning(
          code: "incomplete_person_context",
          message: "The citation proposal was generated from an incomplete person context."
        )
      )
    }
    if !context.conflicts.isEmpty {
      appendUnique(
        &warnings,
        NetworkWarning(
          code: "unresolved_fact_conflicts",
          message: "Review the structured fact conflicts before approving this citation."
        )
      )
    }

    let proposalId = stableID(
      "juuret-proposal", context.contextId, rendered,
      spans.map(\.blockSha256).joined(separator: "|")
    )
    return CitationProposal(
      proposalId: proposalId,
      selectedPerson: selectedPerson,
      renderedText: rendered,
      sourceSpans: spans,
      conflicts: context.conflicts,
      warnings: warnings
    )
  }

  private func render(
    family: Family,
    sourceSpan: SourceSpan,
    selectedPerson: PersonReference,
    claims: [FactClaim]
  ) throws -> String {
    var lines = ["Information on \(pageLabel(family.pageReferences)) includes:"]

    for (coupleIndex, couple) in family.couples.enumerated() {
      if coupleIndex == 0 {
        let husbandSelected = isSelected(selectedPerson, coupleIndex, .parent, 0)
        lines.append(
          formatParent(
            couple.husband,
            arrow: husbandSelected,
            selectedClaims: husbandSelected ? claims : []
          ))
        let wifeSelected = isSelected(selectedPerson, coupleIndex, .parent, 1)
        lines.append(
          formatParent(
            couple.wife,
            arrow: wifeSelected,
            selectedClaims: wifeSelected ? claims : []
          ))
        if let marriage = nonempty(couple.fullMarriageDate ?? couple.marriageDate) {
          lines.append("m. \(formatMarriage(marriage, parentBirthYear: birthYear(couple.husband)))")
        }
      } else {
        lines.append("Additional spouse:")
        let spouse = additionalSpouse(couple, primary: family.primaryCouple)
        lines.append(formatParent(spouse, arrow: false, selectedClaims: []))
        if let marriage = nonempty(couple.fullMarriageDate ?? couple.marriageDate) {
          let parentYear = birthYear(couple.husband) ?? birthYear(couple.wife)
          lines.append("m. \(formatMarriage(marriage, parentBirthYear: parentYear))")
        }
      }

      guard !couple.children.isEmpty else { continue }
      lines.append("Children:")
      for (childIndex, child) in couple.children.enumerated() {
        let childSelected = isSelected(
          selectedPerson, coupleIndex, .child, childIndex)
        let spouseSelected = isSelected(
          selectedPerson, coupleIndex, .spouse, childIndex)
        lines.append(
          formatChild(
            child,
            childArrow: childSelected,
            spouseArrow: spouseSelected,
            selectedClaims: childSelected ? claims : []
          ))
      }
    }

    appendNotes(family, to: &lines)
    appendSupplementalSources(
      primarySpan: sourceSpan,
      selectedName: selectedPerson.rawName,
      claims: claims,
      to: &lines
    )
    return lines.joined(separator: "\n")
  }

  private func formatParent(
    _ person: Person,
    arrow: Bool,
    selectedClaims: [FactClaim]
  ) -> String {
    let birth = person.birthDate
    let death = preferredValue("deathDate", in: selectedClaims) ?? person.deathDate
    var line = (arrow ? "→ " : "") + person.displayName
    if let birth = nonempty(birth), let death = nonempty(death) {
      line += ", \(formatDate(birth)) - \(formatDate(death))"
    } else if let birth = nonempty(birth) {
      line += ", b. \(formatDate(birth))"
    } else if let death = nonempty(death) {
      line += ", d. \(formatDate(death))"
    }
    return line + markers(person.noteMarkers)
  }

  private func formatChild(
    _ child: Person,
    childArrow: Bool,
    spouseArrow: Bool,
    selectedClaims: [FactClaim]
  ) -> String {
    let birth = child.birthDate
    let death = preferredValue("deathDate", in: selectedClaims) ?? child.deathDate
    let marriage = preferredValue("marriageDate", in: selectedClaims) ?? child.bestMarriageDate
    var line = (childArrow ? "→ " : "") + child.name
    if let birth = nonempty(birth), let death = nonempty(death) {
      line += ", \(formatDate(birth)) - \(formatDate(death))"
    } else if let birth = nonempty(birth) {
      line += ", b. \(formatDate(birth))"
    } else if let death = nonempty(death) {
      line += ", d. \(formatDate(death))"
    }
    if let spouse = nonempty(child.spouse) {
      line += ", m. \(spouseArrow ? "→ " : "")\(spouse)"
      if let marriage = nonempty(marriage) {
        line += " \(formatMarriage(marriage, parentBirthYear: birthYear(child)))"
      }
    }
    return line + markers(child.noteMarkers)
  }

  private func appendNotes(_ family: Family, to lines: inout [String]) {
    let notes = family.notes.filter { !$0.lowercased().contains("leski") }
    guard !notes.isEmpty || !family.noteDefinitions.isEmpty else { return }
    lines.append("Note:")
    lines += notes.map(JuuretCitationFormatting.footnoteText)
    for key in family.noteDefinitions.keys.sorted() {
      if let value = family.noteDefinitions[key] {
        lines.append("\(JuuretCitationFormatting.footnoteMarker(key)) \(value)")
      }
    }
  }

  // The page-display policy is intentionally isolated pending final user confirmation.
  private func appendSupplementalSources(
    primarySpan: SourceSpan,
    selectedName: String,
    claims: [FactClaim],
    to lines: inout [String]
  ) {
    let supplemental = claims.filter {
      $0.sourceSpan.blockSha256 != primarySpan.blockSha256
        && ($0.field == "marriageDate" || $0.field == "deathDate")
    }
    guard !supplemental.isEmpty else { return }
    var grouped: [(SourceSpan, Set<String>)] = []
    for claim in supplemental {
      if let index = grouped.firstIndex(where: {
        $0.0.blockSha256 == claim.sourceSpan.blockSha256
      }) {
        grouped[index].1.insert(claim.field)
      } else {
        grouped.append((claim.sourceSpan, [claim.field]))
      }
    }
    lines.append("Additional information:")
    for (span, fields) in grouped {
      let description: String
      if fields == ["marriageDate", "deathDate"] {
        description = "marriage and death dates are"
      } else if fields.contains("marriageDate") {
        description = "marriage date is"
      } else {
        description = "death date is"
      }
      lines.append("\(selectedName)'s \(description) on \(pageLabel(span.pageReferences))")
    }
  }

  private func validate(_ reference: PersonReference, in family: Family) throws {
    guard family.couples.indices.contains(reference.coupleIndex) else {
      throw CitationServiceError.invalidSelectedPerson("couple index is out of range")
    }
    let couple = family.couples[reference.coupleIndex]
    let actual: Person
    switch reference.role {
    case .parent:
      guard (0...1).contains(reference.personIndex) else {
        throw CitationServiceError.invalidSelectedPerson("parent index must be 0 or 1")
      }
      actual = reference.personIndex == 0 ? couple.husband : couple.wife
    case .child:
      guard couple.children.indices.contains(reference.personIndex) else {
        throw CitationServiceError.invalidSelectedPerson("child index is out of range")
      }
      actual = couple.children[reference.personIndex]
    case .spouse:
      guard couple.children.indices.contains(reference.personIndex),
        let spouse = nonempty(couple.children[reference.personIndex].spouse)
      else {
        throw CitationServiceError.invalidSelectedPerson("spouse is absent at the child index")
      }
      actual = Person(name: spouse)
    }
    guard actual.name == reference.rawName else {
      throw CitationServiceError.invalidSelectedPerson("raw name does not match the indexed person")
    }
  }

  private func citationTarget(
    in context: PersonContextResolution,
    selectedPerson: PersonReference
  ) throws -> PersonReference {
    guard selectedPerson.role == .parent || selectedPerson.role == .spouse else {
      return selectedPerson
    }
    if let matched = context.edges.first(where: {
      $0.direction == .asChild && $0.status == .resolved
        && $0.sourcePerson == selectedPerson && $0.matchedPerson != nil
    })?.matchedPerson {
      return matched
    }
    throw CitationServiceError.asChildCitationRequired(
      requiredAsChildFamilyId(in: context, selectedPerson: selectedPerson)
        ?? selectedPerson.rawName)
  }

  private func requiredAsChildFamilyId(
    in context: PersonContextResolution,
    selectedPerson: PersonReference
  ) -> String? {
    if let record = context.families.first(where: {
      familyKey($0.familyId) == familyKey(selectedPerson.familyId)
    }), record.parsedFamily.couples.indices.contains(selectedPerson.coupleIndex) {
      let couple = record.parsedFamily.couples[selectedPerson.coupleIndex]
      switch selectedPerson.role {
      case .parent:
        let person = selectedPerson.personIndex == 0 ? couple.husband : couple.wife
        if let familyId = nonempty(person.asChild) { return familyId }
      case .spouse:
        if couple.children.indices.contains(selectedPerson.personIndex),
          let familyId = nonempty(couple.children[selectedPerson.personIndex].spouseParentsFamilyId)
        {
          return familyId
        }
      case .child:
        break
      }
    }
    return context.edges.first {
      $0.direction == .asChild && $0.sourcePerson == selectedPerson
    }?.toFamilyId
  }

  private func sourceSpans(
    startingWith starting: SourceSpan,
    claims: [FactClaim],
    conflicts: [FactConflict]
  ) -> [SourceSpan] {
    var seen = Set<String>()
    let ordered =
      [starting] + claims.map(\.sourceSpan)
      + conflicts.flatMap { $0.claims.map(\.sourceSpan) }
    return ordered.filter { seen.insert($0.blockSha256).inserted }
  }

  private func preferredValue(_ field: String, in claims: [FactClaim]) -> String? {
    claims.first { $0.field == field && $0.derivation == .referenceHarvested }?.value
      ?? directPreferredValue(field, in: claims)
  }

  private func directPreferredValue(_ field: String, in claims: [FactClaim]) -> String? {
    claims.first { $0.field == field && $0.derivation != .referenceHarvested }?.value
  }

  private func isSelected(
    _ reference: PersonReference,
    _ coupleIndex: Int,
    _ role: PersonRole,
    _ personIndex: Int
  ) -> Bool {
    reference.coupleIndex == coupleIndex && reference.role == role
      && reference.personIndex == personIndex
  }

  private func additionalSpouse(_ couple: Couple, primary: Couple?) -> Person {
    guard let primary else { return couple.wife }
    if samePerson(couple.husband, primary.husband) || samePerson(couple.husband, primary.wife) {
      return couple.wife
    }
    if samePerson(couple.wife, primary.husband) || samePerson(couple.wife, primary.wife) {
      return couple.husband
    }
    return couple.wife
  }

  private func samePerson(_ lhs: Person, _ rhs: Person) -> Bool {
    lhs.displayName == rhs.displayName && lhs.birthDate == rhs.birthDate
  }

  private func pageLabel(_ pages: [String]) -> String {
    pages.count == 1 ? "page \(pages[0])" : "pages \(pages.joined(separator: ", "))"
  }

  private func markers(_ values: [String]) -> String {
    values.isEmpty
      ? "" : " " + values.map(JuuretCitationFormatting.footnoteMarker).joined(separator: " ")
  }

  private func formatDate(_ raw: String, parentBirthYear: Int? = nil) -> String {
    JuuretCitationFormatting.date(raw, parentBirthYear: parentBirthYear)
  }

  private func formatMarriage(_ raw: String, parentBirthYear: Int?) -> String {
    JuuretCitationFormatting.marriageDate(raw, parentBirthYear: parentBirthYear)
  }

  private func birthYear(_ person: Person) -> Int? {
    JuuretCitationFormatting.birthYear(from: person.birthDate)
  }

  private func nonempty(_ value: String?) -> String? {
    guard let result = value?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty
    else { return nil }
    return result
  }

  private func familyKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  private func appendUnique(_ warnings: inout [NetworkWarning], _ warning: NetworkWarning) {
    if !warnings.contains(warning) { warnings.append(warning) }
  }

  private func stableID(_ parts: String...) -> String {
    let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
      .map { String(format: "%02x", $0) }.joined()
    return "\(parts[0])-\(digest.prefix(24))"
  }
}
