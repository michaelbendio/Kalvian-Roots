import CryptoKit
import Foundation

public struct TraversalLimits: Codable, Equatable, Sendable {
  public let maxFamilies: Int
  public let maxDepth: Int
  public let maxElapsedSeconds: Int

  public init(maxFamilies: Int, maxDepth: Int, maxElapsedSeconds: Int) {
    self.maxFamilies = maxFamilies
    self.maxDepth = maxDepth
    self.maxElapsedSeconds = maxElapsedSeconds
  }

  public var isValid: Bool {
    (1...25).contains(maxFamilies) && (0...10).contains(maxDepth)
      && (1...300).contains(maxElapsedSeconds)
  }
}

public enum PersonRole: String, Codable, Sendable {
  case parent
  case child
  case spouse
}

public struct PersonReference: Codable, Hashable, Sendable {
  public let familyId: String
  public let coupleIndex: Int
  public let role: PersonRole
  public let personIndex: Int
  public let rawName: String
  public let rawBirthDate: String?
  public let rawPatronymic: String?
  public let familySearchId: String?

  public init(
    familyId: String,
    coupleIndex: Int,
    role: PersonRole,
    personIndex: Int,
    rawName: String,
    rawBirthDate: String? = nil,
    rawPatronymic: String? = nil,
    familySearchId: String? = nil
  ) {
    self.familyId = familyId
    self.coupleIndex = coupleIndex
    self.role = role
    self.personIndex = personIndex
    self.rawName = rawName
    self.rawBirthDate = rawBirthDate
    self.rawPatronymic = rawPatronymic
    self.familySearchId = familySearchId
  }
}

public struct NetworkWarning: Codable, Equatable, Sendable {
  public let code: String
  public let message: String
  public let details: [String: String]?

  public init(code: String, message: String, details: [String: String]? = nil) {
    self.code = code
    self.message = message
    self.details = details
  }
}

public enum ClaimDerivation: String, Codable, Sendable {
  case direct
  case aiParsed
  case referenceHarvested
}

public struct FactClaim: Codable, Equatable, Sendable {
  public let claimId: String
  public let subjectRef: PersonReference
  public let field: String
  public let value: String
  public let sourceSpan: SourceSpan
  public let sourceFieldPath: String
  public let derivation: ClaimDerivation
  public let parserSchemaVersion: String?
  public let parserImplementationVersion: String?
  public let warnings: [NetworkWarning]

  public init(
    claimId: String,
    subjectRef: PersonReference,
    field: String,
    value: String,
    sourceSpan: SourceSpan,
    sourceFieldPath: String,
    derivation: ClaimDerivation,
    parserSchemaVersion: String?,
    parserImplementationVersion: String?,
    warnings: [NetworkWarning] = []
  ) {
    self.claimId = claimId
    self.subjectRef = subjectRef
    self.field = field
    self.value = value
    self.sourceSpan = sourceSpan
    self.sourceFieldPath = sourceFieldPath
    self.derivation = derivation
    self.parserSchemaVersion = parserSchemaVersion
    self.parserImplementationVersion = parserImplementationVersion
    self.warnings = warnings
  }
}

public struct FactConflict: Codable, Equatable, Sendable {
  public let subjectRef: PersonReference
  public let field: String
  public let reason: String
  public let claims: [FactClaim]

  public init(subjectRef: PersonReference, field: String, reason: String, claims: [FactClaim]) {
    self.subjectRef = subjectRef
    self.field = field
    self.reason = reason
    self.claims = claims
  }
}

public enum FamilyReferenceDirection: String, Codable, Sendable {
  case asChild = "as_child"
  case asParent = "as_parent"
}

public enum FamilyReferenceStatus: String, Codable, Sendable {
  case resolved
  case missing
  case mismatch
  case ambiguous
  case cycle
  case limitReached = "limit_reached"
}

public struct FamilyReferenceEdge: Codable, Equatable, Sendable {
  public let fromFamilyId: String
  public let toFamilyId: String
  public let direction: FamilyReferenceDirection
  public let rawReference: String
  public let sourcePerson: PersonReference
  public let status: FamilyReferenceStatus
  public let matchedPerson: PersonReference?

  public init(
    fromFamilyId: String,
    toFamilyId: String,
    direction: FamilyReferenceDirection,
    rawReference: String,
    sourcePerson: PersonReference,
    status: FamilyReferenceStatus,
    matchedPerson: PersonReference? = nil
  ) {
    self.fromFamilyId = fromFamilyId
    self.toFamilyId = toFamilyId
    self.direction = direction
    self.rawReference = rawReference
    self.sourcePerson = sourcePerson
    self.status = status
    self.matchedPerson = matchedPerson
  }
}

public struct FamilyNetworkResolution: Codable, Equatable, Sendable {
  public let resolutionId: String
  public let startingFamilyId: String
  public let complete: Bool
  public let families: [ParsedFamilyRecord]
  public let edges: [FamilyReferenceEdge]
  public let missingReferences: [NetworkWarning]
  public let cycles: [[String]]
  public let claims: [FactClaim]
  public let conflicts: [FactConflict]

  // Operational telemetry is intentionally excluded from the public contract.
  public let externalServicesContacted: [String]
  public let cacheStatuses: [String]

  public init(
    resolutionId: String, startingFamilyId: String, complete: Bool,
    families: [ParsedFamilyRecord], edges: [FamilyReferenceEdge],
    missingReferences: [NetworkWarning], cycles: [[String]], claims: [FactClaim],
    conflicts: [FactConflict], externalServicesContacted: [String] = [],
    cacheStatuses: [String] = []
  ) {
    self.resolutionId = resolutionId
    self.startingFamilyId = startingFamilyId
    self.complete = complete
    self.families = families
    self.edges = edges
    self.missingReferences = missingReferences
    self.cycles = cycles
    self.claims = claims
    self.conflicts = conflicts
    self.externalServicesContacted = externalServicesContacted
    self.cacheStatuses = cacheStatuses
  }

  private enum CodingKeys: String, CodingKey {
    case resolutionId, startingFamilyId, complete, families, edges, missingReferences, cycles
    case claims, conflicts
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    resolutionId = try container.decode(String.self, forKey: .resolutionId)
    startingFamilyId = try container.decode(String.self, forKey: .startingFamilyId)
    complete = try container.decode(Bool.self, forKey: .complete)
    families = try container.decode([ParsedFamilyRecord].self, forKey: .families)
    edges = try container.decode([FamilyReferenceEdge].self, forKey: .edges)
    missingReferences = try container.decode([NetworkWarning].self, forKey: .missingReferences)
    cycles = try container.decode([[String]].self, forKey: .cycles)
    claims = try container.decode([FactClaim].self, forKey: .claims)
    conflicts = try container.decode([FactConflict].self, forKey: .conflicts)
    externalServicesContacted = []
    cacheStatuses = []
  }
}

public struct PersonContextResolution: Codable, Equatable, Sendable {
  public let contextId: String
  public let selectedPerson: PersonReference
  public let complete: Bool
  public let families: [ParsedFamilyRecord]
  public let claims: [FactClaim]
  public let conflicts: [FactConflict]

  public let missingReferences: [NetworkWarning]
  public let cycles: [[String]]
  public let externalServicesContacted: [String]
  public let cacheStatuses: [String]

  public init(
    contextId: String, selectedPerson: PersonReference, complete: Bool,
    families: [ParsedFamilyRecord], claims: [FactClaim], conflicts: [FactConflict],
    missingReferences: [NetworkWarning] = [], cycles: [[String]] = [],
    externalServicesContacted: [String] = [], cacheStatuses: [String] = []
  ) {
    self.contextId = contextId
    self.selectedPerson = selectedPerson
    self.complete = complete
    self.families = families
    self.claims = claims
    self.conflicts = conflicts
    self.missingReferences = missingReferences
    self.cycles = cycles
    self.externalServicesContacted = externalServicesContacted
    self.cacheStatuses = cacheStatuses
  }

  private enum CodingKeys: String, CodingKey {
    case contextId, selectedPerson, complete, families, claims, conflicts
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    contextId = try container.decode(String.self, forKey: .contextId)
    selectedPerson = try container.decode(PersonReference.self, forKey: .selectedPerson)
    complete = try container.decode(Bool.self, forKey: .complete)
    families = try container.decode([ParsedFamilyRecord].self, forKey: .families)
    claims = try container.decode([FactClaim].self, forKey: .claims)
    conflicts = try container.decode([FactConflict].self, forKey: .conflicts)
    missingReferences = []
    cycles = []
    externalServicesContacted = []
    cacheStatuses = []
  }
}

public enum FamilyNetworkError: Error, Equatable, Sendable {
  case invalidLimits
  case invalidPersonReference(String)

  public var code: String { "invalid_request" }
}

extension FamilyNetworkError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidLimits:
      return "Traversal limits are outside the allowed ranges."
    case .invalidPersonReference(let reason):
      return "The selected person reference is invalid: \(reason)"
    }
  }
}

public protocol FamilyNetworkServing: Sendable {
  func resolveFamilyReferences(
    startingFamily: ParsedFamilyRecord,
    limits: TraversalLimits
  ) async throws -> FamilyNetworkResolution

  func resolvePersonContext(
    person: PersonReference,
    startingFamily: ParsedFamilyRecord,
    limits: TraversalLimits
  ) async throws -> PersonContextResolution
}

public struct FamilyNetworkService: FamilyNetworkServing, Sendable {
  private let bookTextService: any BookTextServing
  private let parsingService: any FamilyParsingServing
  private let now: @Sendable () -> Date

  public init(
    bookTextService: any BookTextServing,
    parsingService: any FamilyParsingServing,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.bookTextService = bookTextService
    self.parsingService = parsingService
    self.now = now
  }

  public func resolveFamilyReferences(
    startingFamily: ParsedFamilyRecord,
    limits: TraversalLimits
  ) async throws -> FamilyNetworkResolution {
    let state = try await traverse(
      startingFamily: startingFamily, selectedPerson: nil, limits: limits)
    return FamilyNetworkResolution(
      resolutionId: stableID(
        "resolution", startingFamily.familyId, startingFamily.source.sha256,
        String(limits.maxFamilies), String(limits.maxDepth), String(limits.maxElapsedSeconds)),
      startingFamilyId: startingFamily.familyId,
      complete: state.complete,
      families: state.families,
      edges: state.edges,
      missingReferences: state.warnings,
      cycles: state.cycles,
      claims: state.claims,
      conflicts: conflicts(in: state.claims),
      externalServicesContacted: state.externalServices.sorted(),
      cacheStatuses: state.cacheStatuses
    )
  }

  public func resolvePersonContext(
    person: PersonReference,
    startingFamily: ParsedFamilyRecord,
    limits: TraversalLimits
  ) async throws -> PersonContextResolution {
    let selected = try locate(person, in: startingFamily.parsedFamily)
    try validateSuppliedReference(person, against: selected.reference)
    let selectedReference = selected.reference
    let state = try await traverse(
      startingFamily: startingFamily, selectedPerson: selectedReference, limits: limits
    )
    let selectedClaims = state.claims.filter { $0.subjectRef == selectedReference }
    return PersonContextResolution(
      contextId: stableID(
        "context", startingFamily.familyId, personKey(selectedReference),
        startingFamily.source.sha256
      ),
      selectedPerson: selectedReference,
      complete: state.complete,
      families: state.families,
      claims: selectedClaims,
      conflicts: conflicts(in: selectedClaims),
      missingReferences: state.warnings,
      cycles: state.cycles,
      externalServicesContacted: state.externalServices.sorted(),
      cacheStatuses: state.cacheStatuses
    )
  }

  private struct LocatedPerson {
    let reference: PersonReference
    let person: Person
    let fieldPath: String
    let couple: Couple
    let relatedSpouse: Person?
  }

  private struct Pending: Sendable {
    let record: ParsedFamilyRecord
    let depth: Int
    let path: [String]
    let focus: PersonReference?
  }

  private struct State {
    var complete = true
    var families: [ParsedFamilyRecord] = []
    var edges: [FamilyReferenceEdge] = []
    var warnings: [NetworkWarning] = []
    var cycles: [[String]] = []
    var claims: [FactClaim] = []
    var externalServices: Set<String> = []
    var cacheStatuses: [String] = []
  }

  private struct ReferenceTask {
    let direction: FamilyReferenceDirection
    let rawReference: String
    let source: LocatedPerson
  }

  private func traverse(
    startingFamily: ParsedFamilyRecord,
    selectedPerson: PersonReference?,
    limits: TraversalLimits
  ) async throws -> State {
    guard limits.isValid else { throw FamilyNetworkError.invalidLimits }
    let startedAt = now()
    var state = State(families: [startingFamily])
    var loaded: [String: ParsedFamilyRecord] = [familyKey(startingFamily.familyId): startingFamily]
    var pending = [
      Pending(
        record: startingFamily, depth: 0, path: [startingFamily.familyId], focus: selectedPerson
      )
    ]
    var pendingIndex = 0

    if let selectedPerson {
      let located = try locate(selectedPerson, in: startingFamily.parsedFamily)
      state.claims += directClaims(for: located, record: startingFamily, subject: selectedPerson)
    } else {
      state.claims += allDirectClaims(in: startingFamily)
    }

    traversal: while pendingIndex < pending.count {
      if now().timeIntervalSince(startedAt) >= Double(limits.maxElapsedSeconds) {
        state.complete = false
        state.warnings.append(limitWarning("maxElapsedSeconds", limits.maxElapsedSeconds))
        break
      }
      let item = pending[pendingIndex]
      pendingIndex += 1
      let tasks = try referenceTasks(in: item.record, focus: item.focus)

      for task in tasks {
        if now().timeIntervalSince(startedAt) >= Double(limits.maxElapsedSeconds) {
          state.complete = false
          appendUnique(
            &state.warnings, limitWarning("maxElapsedSeconds", limits.maxElapsedSeconds)
          )
          break traversal
        }
        let targetKey = familyKey(task.rawReference)
        if item.path.map(familyKey).contains(targetKey) {
          let cycle = cyclePath(item.path, target: task.rawReference)
          if !state.cycles.contains(cycle) { state.cycles.append(cycle) }
          state.edges.append(
            edge(task, from: item.record.familyId, to: task.rawReference, status: .cycle))
          continue
        }
        if item.depth >= limits.maxDepth {
          state.complete = false
          state.edges.append(
            edge(task, from: item.record.familyId, to: task.rawReference, status: .limitReached))
          appendUnique(&state.warnings, limitWarning("maxDepth", limits.maxDepth))
          continue
        }

        let targetRecord: ParsedFamilyRecord
        if let existing = loaded[targetKey] {
          targetRecord = existing
        } else {
          guard state.families.count < limits.maxFamilies else {
            state.complete = false
            state.edges.append(
              edge(task, from: item.record.familyId, to: task.rawReference, status: .limitReached))
            appendUnique(&state.warnings, limitWarning("maxFamilies", limits.maxFamilies))
            continue
          }
          do {
            let source = try await bookTextService.getFamilyText(
              familyId: task.rawReference, expectedSourceSHA256: startingFamily.source.sha256
            )
            let preexisting = try await parsingService.getParsedFamily(
              familyId: source.familyId, sourceSHA256: source.source.sha256
            )
            targetRecord = try await parsingService.parseFamily(
              source: source, cachePolicy: .useValidated)
            if preexisting != nil {
              state.cacheStatuses.append("validated_hit")
            } else if targetRecord.parserImplementationVersion == "legacy-schema2-unknown" {
              state.cacheStatuses.append("legacy_import")
            } else {
              state.cacheStatuses.append("write")
              state.externalServices.insert("DeepSeek")
            }
            loaded[targetKey] = targetRecord
            state.families.append(targetRecord)
          } catch let error as BookTextError {
            let warning = NetworkWarning(
              code: "missing_reference",
              message:
                "\(item.record.familyId) references \(task.rawReference), but it could not be loaded.",
              details: ["familyId": task.rawReference, "reason": error.code]
            )
            state.warnings.append(warning)
            state.edges.append(
              edge(task, from: item.record.familyId, to: task.rawReference, status: .missing))
            continue
          }
        }

        let matches = match(task, in: targetRecord.parsedFamily)
        guard matches.count == 1, let matched = matches.first else {
          let status: FamilyReferenceStatus = matches.isEmpty ? .mismatch : .ambiguous
          let code = matches.isEmpty ? "reference_target_mismatch" : "ambiguous_reference_target"
          state.warnings.append(
            NetworkWarning(
              code: code,
              message:
                "\(task.rawReference) did not resolve to exactly one expected person or couple.",
              details: [
                "fromFamilyId": item.record.familyId, "targetFamilyId": targetRecord.familyId,
              ]
            ))
          state.edges.append(
            edge(task, from: item.record.familyId, to: targetRecord.familyId, status: status))
          continue
        }

        state.edges.append(
          edge(
            task, from: item.record.familyId, to: targetRecord.familyId,
            status: .resolved, matched: matched.reference
          ))
        state.claims += harvestedClaims(
          for: matched, record: targetRecord, subject: task.source.reference,
          direction: task.direction
        )

        if loaded[targetKey]?.familyId == targetRecord.familyId,
          !pending.contains(where: { familyKey($0.record.familyId) == targetKey })
        {
          let nextFocus = selectedPerson == nil ? nil : matched.reference
          pending.append(
            Pending(
              record: targetRecord, depth: item.depth + 1,
              path: item.path + [targetRecord.familyId], focus: nextFocus
            ))
          if selectedPerson == nil { state.claims += allDirectClaims(in: targetRecord) }
        }
      }
    }
    for warning in duplicateWarnings(families: state.families, edges: state.edges) {
      appendUnique(&state.warnings, warning)
    }
    return state
  }

  private func referenceTasks(
    in record: ParsedFamilyRecord,
    focus: PersonReference?
  ) throws -> [ReferenceTask] {
    let people: [LocatedPerson]
    if let focus {
      people = [try locate(focus, in: record.parsedFamily)]
    } else {
      people = allLocatedPeople(in: record.parsedFamily)
    }
    var tasks: [ReferenceTask] = []
    for located in people {
      if let value = nonempty(located.person.asChild) {
        tasks.append(ReferenceTask(direction: .asChild, rawReference: value, source: located))
      }
      if let value = nonempty(located.person.asParent) {
        tasks.append(ReferenceTask(direction: .asParent, rawReference: value, source: located))
      }
      if located.reference.role == .spouse,
        let value = nonempty(located.person.spouseParentsFamilyId)
      {
        tasks.append(ReferenceTask(direction: .asChild, rawReference: value, source: located))
      }
    }
    return tasks
  }

  private func match(_ task: ReferenceTask, in family: Family) -> [LocatedPerson] {
    let candidates = allLocatedPeople(in: family).filter {
      task.direction == .asParent ? $0.reference.role == .parent : $0.reference.role == .child
    }
    let scored = candidates.compactMap { candidate -> (LocatedPerson, Int)? in
      guard namesEqual(task.source.person.name, candidate.person.name) else { return nil }
      let birthMatches = bothEqual(task.source.person.birthDate, candidate.person.birthDate)
      let idMatches = bothEqual(task.source.person.familySearchId, candidate.person.familySearchId)
      let spouseMatches = relationshipMatches(task.source, candidate)
      // A FamilySearch progress annotation may break a tie, but is never an identity key.
      guard birthMatches || spouseMatches else { return nil }
      return (candidate, (birthMatches ? 4 : 0) + (idMatches ? 3 : 0) + (spouseMatches ? 2 : 0))
    }
    guard let best = scored.map(\.1).max() else { return [] }
    return scored.filter { $0.1 == best }.map(\.0)
  }

  private func relationshipMatches(_ source: LocatedPerson, _ candidate: LocatedPerson) -> Bool {
    guard let sourceSpouse = nonempty(source.person.spouse),
      let candidateSpouse = candidate.relatedSpouse
    else {
      return false
    }
    let sourceGiven =
      sourceSpouse.split(whereSeparator: \Character.isWhitespace).first.map(String.init)
      ?? sourceSpouse
    return namesEqual(sourceGiven, candidateSpouse.name)
  }

  private func allLocatedPeople(in family: Family) -> [LocatedPerson] {
    var result: [LocatedPerson] = []
    for (coupleIndex, couple) in family.couples.enumerated() {
      result.append(
        locatedParent(
          couple.husband, index: 0, coupleIndex: coupleIndex, couple: couple,
          familyId: family.familyId))
      result.append(
        locatedParent(
          couple.wife, index: 1, coupleIndex: coupleIndex, couple: couple, familyId: family.familyId
        ))
      for (childIndex, child) in couple.children.enumerated() {
        result.append(
          LocatedPerson(
            reference: reference(
              child, familyId: family.familyId, coupleIndex: coupleIndex,
              role: .child, personIndex: childIndex),
            person: child, fieldPath: "couples[\(coupleIndex)].children[\(childIndex)]",
            couple: couple, relatedSpouse: nil
          ))
      }
    }
    return result
  }

  private func locatedParent(
    _ person: Person, index: Int, coupleIndex: Int, couple: Couple, familyId: String
  ) -> LocatedPerson {
    LocatedPerson(
      reference: reference(
        person, familyId: familyId, coupleIndex: coupleIndex,
        role: .parent, personIndex: index),
      person: person,
      fieldPath: "couples[\(coupleIndex)].\(index == 0 ? "husband" : "wife")",
      couple: couple,
      relatedSpouse: index == 0 ? couple.wife : couple.husband
    )
  }

  private func locate(_ reference: PersonReference, in family: Family) throws -> LocatedPerson {
    guard familyKey(reference.familyId) == familyKey(family.familyId),
      family.couples.indices.contains(reference.coupleIndex)
    else {
      throw FamilyNetworkError.invalidPersonReference("family or couple index does not match")
    }
    let couple = family.couples[reference.coupleIndex]
    let located: LocatedPerson
    switch reference.role {
    case .parent:
      guard (0...1).contains(reference.personIndex) else {
        throw FamilyNetworkError.invalidPersonReference("parent index must be 0 or 1")
      }
      let person = reference.personIndex == 0 ? couple.husband : couple.wife
      located = locatedParent(
        person, index: reference.personIndex,
        coupleIndex: reference.coupleIndex, couple: couple, familyId: family.familyId)
    case .child:
      guard couple.children.indices.contains(reference.personIndex) else {
        throw FamilyNetworkError.invalidPersonReference("child index is out of range")
      }
      let person = couple.children[reference.personIndex]
      located = LocatedPerson(
        reference: self.reference(
          person, familyId: family.familyId,
          coupleIndex: reference.coupleIndex, role: .child, personIndex: reference.personIndex),
        person: person,
        fieldPath: "couples[\(reference.coupleIndex)].children[\(reference.personIndex)]",
        couple: couple, relatedSpouse: nil
      )
    case .spouse:
      guard couple.children.indices.contains(reference.personIndex),
        let spouseName = nonempty(couple.children[reference.personIndex].spouse)
      else {
        throw FamilyNetworkError.invalidPersonReference("spouse is absent at the child index")
      }
      let child = couple.children[reference.personIndex]
      let person = Person(
        name: spouseName, birthDate: child.spouseBirthDate,
        familySearchId: child.spouseFamilySearchId,
        spouseParentsFamilyId: child.spouseParentsFamilyId
      )
      located = LocatedPerson(
        reference: self.reference(
          person, familyId: family.familyId,
          coupleIndex: reference.coupleIndex, role: .spouse, personIndex: reference.personIndex),
        person: person,
        fieldPath: "couples[\(reference.coupleIndex)].children[\(reference.personIndex)].spouse",
        couple: couple, relatedSpouse: child
      )
    }
    return located
  }

  private func reference(
    _ person: Person, familyId: String, coupleIndex: Int, role: PersonRole, personIndex: Int
  ) -> PersonReference {
    PersonReference(
      familyId: familyId, coupleIndex: coupleIndex, role: role, personIndex: personIndex,
      rawName: person.name, rawBirthDate: person.birthDate,
      rawPatronymic: person.patronymic, familySearchId: person.familySearchId
    )
  }

  private func validateSuppliedReference(
    _ supplied: PersonReference, against actual: PersonReference
  ) throws {
    guard namesEqual(supplied.rawName, actual.rawName) else {
      throw FamilyNetworkError.invalidPersonReference("rawName does not match the indexed person")
    }
    if let value = nonempty(supplied.rawBirthDate), !bothEqual(value, actual.rawBirthDate) {
      throw FamilyNetworkError.invalidPersonReference(
        "rawBirthDate does not match the indexed person")
    }
    if let value = nonempty(supplied.rawPatronymic), !bothEqual(value, actual.rawPatronymic) {
      throw FamilyNetworkError.invalidPersonReference(
        "rawPatronymic does not match the indexed person")
    }
    if let value = nonempty(supplied.familySearchId), !bothEqual(value, actual.familySearchId) {
      throw FamilyNetworkError.invalidPersonReference(
        "familySearchId does not match the indexed person")
    }
  }

  private func allDirectClaims(in record: ParsedFamilyRecord) -> [FactClaim] {
    allLocatedPeople(in: record.parsedFamily).flatMap {
      directClaims(for: $0, record: record, subject: $0.reference)
    }
  }

  private func directClaims(
    for located: LocatedPerson, record: ParsedFamilyRecord, subject: PersonReference
  ) -> [FactClaim] {
    claims(
      for: located, record: record, subject: subject, derivation: .aiParsed,
      includeCoupleMarriage: located.reference.role == .parent
    )
  }

  private func harvestedClaims(
    for located: LocatedPerson,
    record: ParsedFamilyRecord,
    subject: PersonReference,
    direction: FamilyReferenceDirection
  ) -> [FactClaim] {
    claims(
      for: located, record: record, subject: subject, derivation: .referenceHarvested,
      includeCoupleMarriage: direction == .asParent
    )
  }

  private func claims(
    for located: LocatedPerson,
    record: ParsedFamilyRecord,
    subject: PersonReference,
    derivation: ClaimDerivation,
    includeCoupleMarriage: Bool
  ) -> [FactClaim] {
    var values: [(String, String?, String)] = [
      ("birthDate", located.person.birthDate, "\(located.fieldPath).birthDate"),
      ("deathDate", located.person.deathDate, "\(located.fieldPath).deathDate"),
    ]
    if let full = nonempty(located.person.fullMarriageDate) {
      values.append(("marriageDate", full, "\(located.fieldPath).fullMarriageDate"))
    } else {
      values.append(
        ("marriageDate", located.person.marriageDate, "\(located.fieldPath).marriageDate"))
    }
    if includeCoupleMarriage {
      if let full = nonempty(located.couple.fullMarriageDate) {
        values.append(
          ("marriageDate", full, "couples[\(located.reference.coupleIndex)].fullMarriageDate"))
      } else {
        values.append(
          (
            "marriageDate", located.couple.marriageDate,
            "couples[\(located.reference.coupleIndex)].marriageDate"
          ))
      }
    }
    return values.compactMap { field, rawValue, path in
      guard let value = nonempty(rawValue) else { return nil }
      return FactClaim(
        claimId: stableID("claim", personKey(subject), field, value, record.span.blockSha256, path),
        subjectRef: subject, field: field, value: value, sourceSpan: record.span,
        sourceFieldPath: path, derivation: derivation,
        parserSchemaVersion: record.familySchemaVersion,
        parserImplementationVersion: record.parserImplementationVersion
      )
    }
  }

  private func conflicts(in claims: [FactClaim]) -> [FactConflict] {
    var order: [String] = []
    var groups: [String: [FactClaim]] = [:]
    for claim in claims {
      let key = "\(personKey(claim.subjectRef))|\(claim.field)"
      if groups[key] == nil { order.append(key) }
      if !(groups[key] ?? []).contains(where: {
        $0.value == claim.value && $0.sourceSpan == claim.sourceSpan
      }) {
        groups[key, default: []].append(claim)
      }
    }
    return order.compactMap { key in
      guard let group = groups[key], group.count >= 2 else { return nil }
      let unique = Array(Set(group.map { normalizedValue($0.value) }))
      guard unique.count >= 2 else { return nil }
      if group[0].field == "marriageDate", marriageValuesAreCompatible(group.map(\.value)) {
        return nil
      }
      return FactConflict(
        subjectRef: group[0].subjectRef, field: group[0].field,
        reason: "source_values_disagree", claims: group
      )
    }
  }

  private func marriageValuesAreCompatible(_ values: [String]) -> Bool {
    let tokens = values.compactMap(marriageYearToken)
    guard tokens.count == values.count else { return false }
    let fullYears = Set(tokens.compactMap { $0.isShort ? nil : $0.value })
    let shortYears = Set(tokens.compactMap { $0.isShort ? $0.value : nil })
    if fullYears.count > 1 || shortYears.count > 1 { return false }
    guard let fullYear = fullYears.first, let shortYear = shortYears.first else { return true }
    return fullYear % 100 == shortYear
  }

  private func marriageYearToken(_ value: String) -> (value: Int, isShort: Bool)? {
    let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    guard let last = numbers.last else { return nil }
    if last >= 1000 { return (last, false) }
    if last <= 99 { return (last, true) }
    return nil
  }

  private func edge(
    _ task: ReferenceTask,
    from: String,
    to: String,
    status: FamilyReferenceStatus,
    matched: PersonReference? = nil
  ) -> FamilyReferenceEdge {
    FamilyReferenceEdge(
      fromFamilyId: from, toFamilyId: to, direction: task.direction,
      rawReference: task.rawReference, sourcePerson: task.source.reference,
      status: status, matchedPerson: matched
    )
  }

  private func cyclePath(_ path: [String], target: String) -> [String] {
    let targetKey = familyKey(target)
    let start = path.firstIndex { familyKey($0) == targetKey } ?? 0
    return Array(path[start...]) + [path[start]]
  }

  private func limitWarning(_ name: String, _ value: Int) -> NetworkWarning {
    NetworkWarning(
      code: "traversal_limit_reached",
      message: "Traversal stopped at \(name)=\(value).",
      details: ["limit": name, "value": String(value)]
    )
  }

  private func appendUnique(_ warnings: inout [NetworkWarning], _ warning: NetworkWarning) {
    if !warnings.contains(warning) { warnings.append(warning) }
  }

  private func duplicateWarnings(
    families: [ParsedFamilyRecord], edges: [FamilyReferenceEdge]
  ) -> [NetworkWarning] {
    let people = families.flatMap { allLocatedPeople(in: $0.parsedFamily) }
    var warnings: [NetworkWarning] = []
    let linked = Set(
      edges.compactMap { edge -> String? in
        guard edge.status == .resolved, let matched = edge.matchedPerson else { return nil }
        return undirectedPair(edge.sourcePerson, matched)
      })

    var idGroups: [String: [PersonReference]] = [:]
    var identityGroups: [String: [PersonReference]] = [:]
    for located in people {
      if let id = nonempty(located.person.familySearchId) {
        idGroups[id.uppercased(), default: []].append(located.reference)
      }
      if let birth = nonempty(located.person.birthDate) {
        let identity = "\(located.person.name.lowercased())|\(birth)"
        identityGroups[identity, default: []].append(located.reference)
      }
    }

    for (id, references) in idGroups.sorted(by: { $0.key < $1.key })
    where references.count > 1 && !allLinked(references, by: linked) {
      warnings.append(
        NetworkWarning(
          code: "duplicate_familysearch_id",
          message:
            "FamilySearch progress ID \(id) appears on people not joined by a resolved reference.",
          details: ["familySearchId": id, "count": String(references.count)]
        ))
    }
    for (identity, references) in identityGroups.sorted(by: { $0.key < $1.key })
    where references.count > 1 && !allLinked(references, by: linked) {
      warnings.append(
        NetworkWarning(
          code: "duplicate_person_identity",
          message:
            "The same exact name and birth date appear on people not joined by a resolved reference.",
          details: ["identity": identity, "count": String(references.count)]
        ))
    }
    return warnings
  }

  private func allLinked(_ references: [PersonReference], by links: Set<String>) -> Bool {
    guard let first = references.first else { return true }
    var reached: Set<PersonReference> = [first]
    var changed = true
    while changed {
      changed = false
      for reference in references where !reached.contains(reference) {
        if reached.contains(where: { links.contains(undirectedPair($0, reference)) }) {
          reached.insert(reference)
          changed = true
        }
      }
    }
    return reached.count == Set(references).count
  }

  private func undirectedPair(_ lhs: PersonReference, _ rhs: PersonReference) -> String {
    [personKey(lhs), personKey(rhs)].sorted().joined(separator: "<->")
  }

  private func familyKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  private func personKey(_ reference: PersonReference) -> String {
    "\(familyKey(reference.familyId))|\(reference.coupleIndex)|\(reference.role.rawValue)|\(reference.personIndex)"
  }

  private func nonempty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }

  private func namesEqual(_ lhs: String, _ rhs: String) -> Bool {
    lhs.trimmingCharacters(in: .whitespacesAndNewlines)
      .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
  }

  private func bothEqual(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs = nonempty(lhs), let rhs = nonempty(rhs) else { return false }
    return lhs.caseInsensitiveCompare(rhs) == .orderedSame
  }

  private func normalizedValue(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func stableID(_ parts: String...) -> String {
    let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
      .map { String(format: "%02x", $0) }.joined()
    return "\(parts[0])-\(digest.prefix(24))"
  }
}
