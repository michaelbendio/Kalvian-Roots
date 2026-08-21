import Foundation

public protocol NameCanonicalizing {
  func canonicalName(for name: String) -> String
}

public enum NameEquivalenceRules {
  public static let defaultPairs: [(String, String)] = [
    ("Liisa", "Elisabet"),
    ("Liisa", "Elis."),
    ("Liisa", "Lijsa"),
    ("Liisa", "Lisa"),
    ("Maija", "Maria"),
    ("Malin", "Magdalena"),
    ("Helena", "Leena"),
    ("Tuomas", "Thomas"),
    ("Johan", "Juho"),
    ("Juho", "Johannes"),
    ("Matti", "Matias"),
    ("Matti", "Mats"),
    ("Matti", "Matts"),
    ("Matti", "Matthias"),
    ("Mikko", "Michel"),
    ("Mikko", "Michael"),
    ("Anna", "Annika"),
    ("Kaisa", "Caisa"),
    ("Kustaa", "Kustavi"),
    ("Kustaa", "Gustav"),
    ("Kustaa", "Gustaf"),
    ("Brita", "Birgit"),
    ("Brita", "Briita"),
    ("Brita", "Britha"),
    ("Erik", "Erkki"),
    ("Erik", "Ericus"),
    ("Jaakko", "Jacob"),
    ("Kaarin", "Carin"),
    ("Kaarin", "Catharina"),
    ("Katariina", "Catharina"),
    ("Henrik", "Heikki"),
    ("Henrik", "Henric"),
    ("Henrik", "Hinric"),
    ("Margareta", "Marketta"),
    ("Kristina", "Kirstine"),
    ("Pietari", "Petrus"),
    ("Pietari", "Per"),
    ("Antti", "Anders"),
    ("Antti", "Andreas"),
    ("Elisabet", "Elisabeth"),
    ("Abraham", "Abram"),
  ]
}

public struct BuiltinNameEquivalenceManager: NameCanonicalizing, Sendable {
  private let canonicalByToken: [String: String]

  public init(additionalPairs: [(String, String)] = []) {
    var graph: [String: Set<String>] = [:]
    for (left, right) in NameEquivalenceRules.defaultPairs + additionalPairs {
      let normalizedLeft = Self.normalizeToken(left)
      let normalizedRight = Self.normalizeToken(right)
      guard !normalizedLeft.isEmpty, !normalizedRight.isEmpty else { continue }
      graph[normalizedLeft, default: []].insert(normalizedRight)
      graph[normalizedRight, default: []].insert(normalizedLeft)
    }

    var canonical: [String: String] = [:]
    var visited: Set<String> = []
    for token in graph.keys.sorted() where !visited.contains(token) {
      var component: Set<String> = []
      var queue = [token]
      while let next = queue.popLast() {
        guard visited.insert(next).inserted else { continue }
        component.insert(next)
        queue.append(contentsOf: graph[next, default: []].sorted())
      }
      let representative = component.sorted().first ?? token
      for member in component { canonical[member] = representative }
    }
    canonicalByToken = canonical
  }

  public func canonicalName(for name: String) -> String {
    Self.tokens(name).map { canonicalByToken[$0] ?? $0 }.joined(separator: " ")
  }

  private static func tokens(_ value: String) -> [String] {
    value.split(whereSeparator: \.isWhitespace)
      .map(String.init)
      .map(normalizeToken)
      .filter { !$0.isEmpty }
  }

  private static func normalizeToken(_ token: String) -> String {
    token
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
      .lowercased()
      .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fi_FI"))
  }
}

public enum GenealogyDateParser {
  private static let formats = [
    "d.M.yyyy", "dd.MM.yyyy", "d MMM yyyy", "dd MMM yyyy",
    "d MMMM yyyy", "dd MMMM yyyy", "d. MMM yyyy", "dd. MMM yyyy",
    "d. MMMM yyyy", "dd. MMMM yyyy", "MMM yyyy", "MMMM yyyy", "yyyy",
  ]
  private static let locales = [
    Locale(identifier: "en_US_POSIX"), Locale(identifier: "sv_SE"),
    Locale(identifier: "fi_FI"),
  ]

  public static func parse(_ rawDate: String?) -> Date? {
    guard let trimmed = rawDate?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else { return nil }

    for locale in locales {
      for format in formats where matchesShape(trimmed, format: format) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        formatter.dateFormat = format
        if let date = formatter.date(from: trimmed) { return date }
      }
    }
    return nil
  }

  public static func normalized(_ date: Date?) -> String? {
    guard let date else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func matchesShape(_ value: String, format: String) -> Bool {
    switch format {
    case "d.M.yyyy", "dd.MM.yyyy":
      value.range(of: #"^\d{1,2}\.\d{1,2}\.\d{4}$"#, options: .regularExpression) != nil
    case "d MMM yyyy", "dd MMM yyyy", "d MMMM yyyy", "dd MMMM yyyy",
      "d. MMM yyyy", "dd. MMM yyyy", "d. MMMM yyyy", "dd. MMMM yyyy":
      value.range(of: #"^\d{1,2}\.?\s+\p{L}+\.?\s+\d{4}$"#, options: .regularExpression) != nil
    case "MMM yyyy", "MMMM yyyy":
      value.range(of: #"^\p{L}+\.?\s+\d{4}$"#, options: .regularExpression) != nil
    case "yyyy":
      value.range(of: #"^\d{4}$"#, options: .regularExpression) != nil
    default:
      false
    }
  }
}

public struct PersonIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
  public let canonicalName: String
  public let birthDate: Date?

  public init(name: String, birthDate: Date?, nameManager: any NameCanonicalizing) {
    canonicalName = nameManager.canonicalName(for: name)
    self.birthDate = birthDate
  }

  public func matches(_ other: PersonIdentity) -> Bool {
    guard canonicalName == other.canonicalName,
      let birthDate, let otherBirthDate = other.birthDate
    else { return false }
    return birthDate == otherBirthDate
  }

  public var description: String {
    guard let birthDate = GenealogyDateParser.normalized(birthDate) else {
      return "\(canonicalName) (unknown birth)"
    }
    return "\(canonicalName) (\(birthDate))"
  }
}

public struct PersonCandidate: Hashable, Codable, Sendable, CustomStringConvertible {
  public enum SourceType: String, Codable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
  {
    case familySearch
    case juuretKalvialla
    case hiski

    public var description: String { rawValue }
    public var debugDescription: String { rawValue }
  }

  public let identity: PersonIdentity
  public let source: SourceType
  public let rawName: String
  public let birthDate: Date?
  public let deathDate: Date?
  public let rawBirthDate: String?
  public let rawDeathDate: String?
  public let familySearchId: String?
  public let hiskiCitation: URL?
  public let hiskiCandidateId: String?
  public let provenance: [SourceSpan]

  public init(
    name: String,
    identityName: String? = nil,
    birthDate: Date?,
    deathDate: Date? = nil,
    rawBirthDate: String? = nil,
    rawDeathDate: String? = nil,
    source: SourceType,
    nameManager: any NameCanonicalizing,
    familySearchId: String? = nil,
    hiskiCitation: URL? = nil,
    hiskiCandidateId: String? = nil,
    provenance: [SourceSpan] = []
  ) {
    identity = PersonIdentity(
      name: identityName ?? name, birthDate: birthDate, nameManager: nameManager)
    rawName = name
    self.birthDate = birthDate
    self.deathDate = deathDate
    self.rawBirthDate = rawBirthDate ?? GenealogyDateParser.normalized(birthDate)
    self.rawDeathDate = rawDeathDate ?? GenealogyDateParser.normalized(deathDate)
    self.source = source
    self.familySearchId = familySearchId
    self.hiskiCitation = hiskiCitation
    self.hiskiCandidateId = hiskiCandidateId
    self.provenance = provenance
  }

  public var isFromFamilySearch: Bool { source == .familySearch }
  public var isFromJuuret: Bool { source == .juuretKalvialla }
  public var isFromHiski: Bool { source == .hiski }

  public var description: String {
    [rawName, rawBirthDate, "[\(source.rawValue)]"].compactMap { $0 }.joined(separator: " ")
  }
}

public enum PersonNameComparison {
  public static func candidatesHaveNameMatch(_ left: PersonCandidate, _ right: PersonCandidate) -> Bool {
    if left.identity.canonicalName == right.identity.canonicalName { return true }
    return namesAreNear(left.rawName, right.rawName)
  }

  public static func namesAreNear(_ left: String, _ right: String) -> Bool {
    guard let leftToken = comparableGivenToken(from: left),
      let rightToken = comparableGivenToken(from: right)
    else { return false }
    if leftToken == rightToken { return true }
    let shorterCount = min(leftToken.count, rightToken.count)
    guard shorterCount >= 4 else { return false }
    if leftToken.hasPrefix(rightToken) || rightToken.hasPrefix(leftToken) { return true }
    return commonPrefixCount(leftToken, rightToken) >= 5
  }

  private static func comparableGivenToken(from name: String) -> String? {
    let token = name.split { !$0.isLetter }.first.map(String.init)?
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fi_FI"))
      .filter(\.isLetter)
    guard let token, !token.isEmpty else { return nil }
    return token
  }

  private static func commonPrefixCount(_ left: String, _ right: String) -> Int {
    zip(left, right).prefix { $0 == $1 }.count
  }
}

public struct FamilyComparisonResult: Codable, Equatable, Sendable {
  public struct Match: Codable, Equatable, Sendable {
    public let identity: PersonIdentity
    public let familySearch: PersonCandidate?
    public let juuretKalvialla: PersonCandidate?
    public let hiski: PersonCandidate?

    public init(
      identity: PersonIdentity,
      familySearch: PersonCandidate?,
      juuretKalvialla: PersonCandidate?,
      hiski: PersonCandidate?
    ) {
      self.identity = identity
      self.familySearch = familySearch
      self.juuretKalvialla = juuretKalvialla
      self.hiski = hiski
    }
  }

  public let rows: [Match]
  public let matches: [Match]
  public let familySearchOnly: [PersonCandidate]
  public let juuretOnly: [PersonCandidate]
  public let hiskiOnly: [PersonCandidate]

  public init(
    familySearch: [PersonCandidate],
    juuretKalvialla: [PersonCandidate],
    hiski: [PersonCandidate]
  ) {
    let allCandidates = familySearch + juuretKalvialla + hiski
    var candidateGroups = Self.groupDatedCandidatesByChild(
      allCandidates.filter { $0.birthDate != nil })
    candidateGroups += allCandidates.filter { $0.birthDate == nil }.map { [$0] }

    var rowResults: [Match] = []
    var matchResults: [Match] = []
    var fsOnly: [PersonCandidate] = []
    var jkOnly: [PersonCandidate] = []
    var hkOnly: [PersonCandidate] = []

    for candidates in candidateGroups {
      let fsCandidates = candidates.filter(\.isFromFamilySearch)
      let jkCandidates = candidates.filter(\.isFromJuuret)
      let hkCandidates = candidates.filter(\.isFromHiski)
      let rowCount = max(fsCandidates.count, jkCandidates.count, hkCandidates.count)
      for index in 0..<rowCount {
        let fs = fsCandidates.indices.contains(index) ? fsCandidates[index] : nil
        let jk = jkCandidates.indices.contains(index) ? jkCandidates[index] : nil
        let hk = hkCandidates.indices.contains(index) ? hkCandidates[index] : nil
        guard let identity = fs?.identity ?? jk?.identity ?? hk?.identity else { continue }
        if let fs, jk == nil, hk == nil { fsOnly.append(fs) }
        if let jk, fs == nil, hk == nil { jkOnly.append(jk) }
        if let hk, fs == nil, jk == nil { hkOnly.append(hk) }
        let row = Match(identity: identity, familySearch: fs, juuretKalvialla: jk, hiski: hk)
        rowResults.append(row)
        if [fs, jk, hk].compactMap({ $0 }).count >= 2 { matchResults.append(row) }
      }
    }

    rows = rowResults
    matches = matchResults
    familySearchOnly = fsOnly
    juuretOnly = jkOnly
    hiskiOnly = hkOnly
  }

  private static func groupDatedCandidatesByChild(_ candidates: [PersonCandidate]) -> [[PersonCandidate]] {
    let candidatesByBirthDate = Dictionary(grouping: candidates, by: \.birthDate!)
    return candidatesByBirthDate.keys.sorted().flatMap { birthDate in
      var groups: [[PersonCandidate]] = []
      for candidate in candidatesByBirthDate[birthDate] ?? [] {
        let matches = groups.indices.filter { groupIndex in
          groups[groupIndex].contains { PersonNameComparison.candidatesHaveNameMatch(candidate, $0) }
        }
        guard let firstMatch = matches.first else {
          groups.append([candidate])
          continue
        }
        groups[firstMatch].append(candidate)
        for groupIndex in matches.dropFirst().reversed() {
          groups[firstMatch].append(contentsOf: groups.remove(at: groupIndex))
        }
      }
      return groups
    }
  }
}
