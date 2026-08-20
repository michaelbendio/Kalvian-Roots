import CryptoKit
import Foundation

public enum HiskiEventType: String, Codable, CaseIterable, Sendable {
  case birth
  case marriage
  case death

  var registerName: String {
    switch self {
    case .birth: "kastetut"
    case .marriage: "vihityt"
    case .death: "haudatut"
    }
  }
}

public struct HiskiQueryMotivation: Codable, Equatable, Sendable {
  public let person: PersonReference
  public let juuretField: String
  public let juuretValue: String
  public let sourceSpan: SourceSpan

  public init(
    person: PersonReference,
    juuretField: String,
    juuretValue: String,
    sourceSpan: SourceSpan
  ) {
    self.person = person
    self.juuretField = juuretField
    self.juuretValue = juuretValue
    self.sourceSpan = sourceSpan
  }
}

public struct HiskiQuery: Codable, Equatable, Sendable {
  public let queryId: String
  public let eventType: HiskiEventType
  public let requestedPrimaryName: String
  public let requestedSecondaryName: String?
  public let requestedDate: String
  public let parentBirthYear: Int?
  public let queryPrimaryName: String
  public let querySecondaryName: String?
  public let queryDate: String
  public let searchURL: String
  public let motivation: HiskiQueryMotivation

  public init(
    queryId: String,
    eventType: HiskiEventType,
    requestedPrimaryName: String,
    requestedSecondaryName: String?,
    requestedDate: String,
    parentBirthYear: Int?,
    queryPrimaryName: String,
    querySecondaryName: String?,
    queryDate: String,
    searchURL: String,
    motivation: HiskiQueryMotivation
  ) {
    self.queryId = queryId
    self.eventType = eventType
    self.requestedPrimaryName = requestedPrimaryName
    self.requestedSecondaryName = requestedSecondaryName
    self.requestedDate = requestedDate
    self.parentBirthYear = parentBirthYear
    self.queryPrimaryName = queryPrimaryName
    self.querySecondaryName = querySecondaryName
    self.queryDate = queryDate
    self.searchURL = searchURL
    self.motivation = motivation
  }
}

public struct HiskiResultField: Codable, Equatable, Sendable {
  public let label: String
  public let value: String

  public init(label: String, value: String) {
    self.label = label
    self.value = value
  }
}

public struct HiskiResultCandidate: Codable, Equatable, Sendable {
  public let candidateId: String
  public let eventType: HiskiEventType
  public let recordURL: String
  public let recordPath: String
  public let fields: [HiskiResultField]
  public let rowText: String

  public init(
    candidateId: String,
    eventType: HiskiEventType,
    recordURL: String,
    recordPath: String,
    fields: [HiskiResultField],
    rowText: String
  ) {
    self.candidateId = candidateId
    self.eventType = eventType
    self.recordURL = recordURL
    self.recordPath = recordPath
    self.fields = fields
    self.rowText = rowText
  }
}

public struct HiskiSearchResult: Codable, Equatable, Sendable {
  public let query: HiskiQuery
  public let candidates: [HiskiResultCandidate]
  public let candidateCount: Int
  public let ambiguous: Bool
  public let responseSha256: String

  public init(query: HiskiQuery, candidates: [HiskiResultCandidate], responseSha256: String) {
    self.query = query
    self.candidates = candidates
    self.candidateCount = candidates.count
    self.ambiguous = candidates.count > 1
    self.responseSha256 = responseSha256
  }
}

public struct HiskiRecord: Codable, Equatable, Sendable {
  public let query: HiskiQuery
  public let candidate: HiskiResultCandidate
  public let citationURL: String
  public let fields: [HiskiResultField]
  public let recordText: String
  public let responseSha256: String

  public init(
    query: HiskiQuery,
    candidate: HiskiResultCandidate,
    citationURL: String,
    fields: [HiskiResultField],
    recordText: String,
    responseSha256: String
  ) {
    self.query = query
    self.candidate = candidate
    self.citationURL = citationURL
    self.fields = fields
    self.recordText = recordText
    self.responseSha256 = responseSha256
  }
}

public enum HiskiResearchServiceError: Error, Equatable, Sendable {
  case invalidRequest(String)
  case invalidURL
  case liveNetworkApprovalRequired
  case responseDecodingFailed
  case responseTooLarge
  case serverResponse(Int)
  case citationLinkMissing

  public var code: String {
    switch self {
    case .invalidRequest, .invalidURL: "invalid_request"
    case .liveNetworkApprovalRequired: "approval_required"
    case .responseDecodingFailed, .responseTooLarge, .citationLinkMissing: "source_parse_failed"
    case .serverResponse: "network_error"
    }
  }
}

extension HiskiResearchServiceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let reason): "The HiSki request is invalid: \(reason)"
    case .invalidURL: "The HiSki URL is invalid."
    case .liveNetworkApprovalRequired:
      "Live HiSki access requires allowLiveNetwork to be explicitly true."
    case .responseDecodingFailed: "The HiSki response could not be decoded as Latin-1 text."
    case .responseTooLarge: "The HiSki response exceeded the 2 MB safety limit."
    case .serverResponse(let status): "HiSki returned HTTP status \(status)."
    case .citationLinkMissing: "The HiSki citation link was not found in the detail record."
    }
  }
}

public enum HiskiQueryRules {
  public static let parishes = "0053,0093,0165,0183,0218,0172,0265,0295,0301,0386,0555,0581,0614"
  public static let maxResults = 50

  public static func givenNameSearchInput(for name: String) -> String? {
    switch firstNormalizedToken(in: name) {
    case "malin": "Magdalena"
    case "pietari": "Per"
    default: nil
    }
  }

  public static func patronymicSearchInput(for patronymic: String) -> String? {
    switch firstNormalizedToken(in: patronymic) {
    case "luukkaanp": "Lucason"
    case "luukkaant": "Lucasdr"
    case "pietarinp": "Perss"
    case "pietarint": "Persdr"
    default: nil
    }
  }

  public static func surnameSearchInput(forPatronymic patronymic: String) -> String? {
    switch firstNormalizedToken(in: patronymic) {
    case "luukkaanp": "Lucason"
    case "luukkaant": "Lucasdr"
    default: nil
    }
  }

  public static func queryFirstName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let first = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
    return givenNameSearchInput(for: first) ?? first
  }

  public static func dateForQuery(_ raw: String, parentBirthYear: Int? = nil) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, let day = Int(parts[0]), let month = Int(parts[1]) else {
      return value
    }
    let year: String
    if parts[2].count == 2, let short = Int(parts[2]) {
      year = String(JuuretCitationFormatting.inferCentury(
        for: short, parentBirthYear: parentBirthYear))
    } else {
      year = String(parts[2])
    }
    return "\(day).\(month).\(year)"
  }

  public static func searchURL(
    eventType: HiskiEventType,
    primaryName: String,
    secondaryName: String? = nil,
    date: String
  ) throws -> URL {
    var params = [
      "komento": "haku", "srk": parishes, "kirja": eventType.registerName,
      "kieli": "en", "alkuvuosi": date, "loppuvuosi": date,
      "maxkpl": String(maxResults), "ietunimi": "", "aetunimi": "",
      "ipatronyymi": "", "apatronyymi": "", "isukunimi": "",
      "asukunimi": "", "iammatti": "", "aammatti": "", "ikyla": "",
    ]
    switch eventType {
    case .birth:
      params["etunimi"] = primaryName
      params["ketunimi"] = ""
      params["kpatronyymi"] = ""
      params["ksukunimi"] = ""
      params["kammatti"] = ""
    case .marriage:
      params["ietunimi"] = primaryName
      params["aetunimi"] = secondaryName ?? ""
      params["akyla"] = ""
    case .death:
      params["ietunimi"] = primaryName
      params["ssuhde"] = "ei+v%E4li%E4"
      params["ksyy"] = ""
      params["syntalku"] = ""
      params["syntloppu"] = ""
      params["ika"] = ""
    }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "hiski.genealogia.fi"
    components.path = "/hiski"
    components.queryItems = params.sorted { $0.key < $1.key }.map {
      URLQueryItem(name: $0.key, value: $0.value)
    }
    guard let url = components.url else { throw HiskiResearchServiceError.invalidURL }
    return url
  }

  private static func firstNormalizedToken(in value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).first.map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
      .lowercased()
      .folding(options: .diacriticInsensitive, locale: .current) ?? ""
  }
}

public enum HiskiHTMLParser {
  public static func resultCandidates(
    from html: String,
    eventType: HiskiEventType,
    matchingDate: String? = nil
  ) -> [HiskiResultCandidate] {
    var headers: [String] = []
    var candidates: [HiskiResultCandidate] = []
    for row in tableRows(from: html) {
      let rowHeaders = headerContents(from: row)
      if !rowHeaders.isEmpty {
        headers = rowHeaders
        continue
      }
      guard let path = slGifHref(from: row) else { continue }
      let values = cellContents(from: row).map(cleanCellText)
      if let matchingDate, !values.contains(where: { $0.contains(matchingDate) }) {
        continue
      }
      let fields = values.enumerated().map { index, value in
        HiskiResultField(
          label: index < headers.count && !headers[index].isEmpty
            ? headers[index] : "column_\(index + 1)",
          value: value
        )
      }
      let recordURL = absoluteHiskiURL(path) ?? path
      candidates.append(HiskiResultCandidate(
        candidateId: stableID("hiski-candidate", eventType.rawValue, recordURL, fields.map {
          "\($0.label)=\($0.value)"
        }.joined(separator: "|")),
        eventType: eventType,
        recordURL: recordURL,
        recordPath: path,
        fields: fields,
        rowText: values.filter { !$0.isEmpty }.joined(separator: " | ")
      ))
    }
    return candidates
  }

  public static func slGifHref(from html: String) -> String? {
    let pattern = #"<a\s+[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>\s*<img[^>]+src\s*=\s*[\"'][^\"']*sl\.gif[\"']"#
    return firstCapture(in: html, pattern: pattern)
  }

  public static func citationURL(fromRecordHTML html: String) -> String? {
    let hrefPattern = #"href\s*=\s*[\"'](/hiski\?en\+t\d+)[\"']"#
    if let path = firstCapture(in: html, pattern: hrefPattern) {
      return absoluteHiskiURL(path)
    }
    let eventPattern = #"Link(?:\s|&nbsp;)+to(?:\s|&nbsp;)+this(?:\s|&nbsp;)+event[\s\S]*?\[\s*(\d+)\s*\]"#
    if let code = firstCapture(in: html, pattern: eventPattern) {
      return "https://hiski.genealogia.fi/hiski?en+t\(code)"
    }
    return nil
  }

  public static func recordFields(from html: String) -> [HiskiResultField] {
    tableRows(from: html).compactMap { row in
      let values = cellContents(from: row).map(cleanCellText).filter { !$0.isEmpty }
      guard values.count >= 2 else { return nil }
      return HiskiResultField(label: values[0], value: values.dropFirst().joined(separator: " | "))
    }
  }

  public static func visibleText(from html: String) -> String {
    cleanCellText(html)
  }

  private static func tableRows(from html: String) -> [String] {
    let pattern = #"<tr[^>]*>(.*?)(?=</tr>|<tr[^>]*>|</table>|<form|\z)"#
    guard let regex = try? NSRegularExpression(
      pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    else { return [] }
    return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
      guard let range = Range($0.range, in: html) else { return nil }
      return String(html[range])
    }
  }

  private static func headerContents(from html: String) -> [String] {
    splitCells(html, tag: "th").map(cleanCellText)
  }

  private static func cellContents(from html: String) -> [String] {
    splitCells(html, tag: "td")
  }

  private static func splitCells(_ html: String, tag: String) -> [String] {
    let delimiter = "\u{1F}"
    let separated = html.replacingOccurrences(
      of: "(?i)<\(tag)[^>]*>", with: delimiter, options: .regularExpression)
    return Array(separated.components(separatedBy: delimiter).dropFirst())
  }

  private static func cleanCellText(_ html: String) -> String {
    let noSmall = html.replacingOccurrences(
      of: "(?is)<small[^>]*>.*?</small>", with: " ", options: .regularExpression)
    return noSmall.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&#160;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func firstCapture(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      match.numberOfRanges > 1,
      let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range])
  }

  private static func absoluteHiskiURL(_ value: String) -> String? {
    if value.hasPrefix("https://hiski.genealogia.fi/") { return value }
    guard value.hasPrefix("/hiski?") else { return nil }
    return "https://hiski.genealogia.fi\(value)"
  }
}

public protocol HiskiHTMLFetching: Sendable {
  func html(from url: URL) async throws -> String
}

public struct URLSessionHiskiHTMLFetcher: HiskiHTMLFetching, Sendable {
  public static let maxResponseBytes = 2_000_000

  public init() {}

  public func html(from url: URL) async throws -> String {
    let (data, response) = try await URLSession.shared.data(from: url)
    if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
      throw HiskiResearchServiceError.serverResponse(response.statusCode)
    }
    guard data.count <= Self.maxResponseBytes else {
      throw HiskiResearchServiceError.responseTooLarge
    }
    guard let html = String(data: data, encoding: .isoLatin1) else {
      throw HiskiResearchServiceError.responseDecodingFailed
    }
    return html
  }
}

public protocol HiskiResearchServing: Sendable {
  func buildQuery(
    eventType: HiskiEventType,
    primaryName: String,
    secondaryName: String?,
    date: String,
    parentBirthYear: Int?,
    motivation: HiskiQueryMotivation
  ) throws -> HiskiQuery
  func search(_ query: HiskiQuery, allowLiveNetwork: Bool) async throws -> HiskiSearchResult
  func record(
    for candidate: HiskiResultCandidate,
    query: HiskiQuery,
    allowLiveNetwork: Bool
  ) async throws -> HiskiRecord
}

public struct HiskiResearchService: HiskiResearchServing, Sendable {
  private let fetcher: any HiskiHTMLFetching

  public init(fetcher: any HiskiHTMLFetching = URLSessionHiskiHTMLFetcher()) {
    self.fetcher = fetcher
  }

  public func buildQuery(
    eventType: HiskiEventType,
    primaryName: String,
    secondaryName: String? = nil,
    date: String,
    parentBirthYear: Int? = nil,
    motivation: HiskiQueryMotivation
  ) throws -> HiskiQuery {
    let requestedPrimary = primaryName.trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedSecondary = secondaryName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !requestedPrimary.isEmpty, !requestedDate.isEmpty else {
      throw HiskiResearchServiceError.invalidRequest("name and date are required")
    }
    if eventType == .marriage && (requestedSecondary?.isEmpty != false) {
      throw HiskiResearchServiceError.invalidRequest("marriage queries require a spouse name")
    }
    let primary = HiskiQueryRules.queryFirstName(requestedPrimary)
    let secondary = requestedSecondary.map(HiskiQueryRules.queryFirstName)
    let queryDate = HiskiQueryRules.dateForQuery(requestedDate, parentBirthYear: parentBirthYear)
    let url = try HiskiQueryRules.searchURL(
      eventType: eventType, primaryName: primary, secondaryName: secondary, date: queryDate)
    let queryId = stableID(
      "hiski-query", eventType.rawValue, requestedPrimary, requestedSecondary ?? "", requestedDate,
      url.absoluteString, motivation.sourceSpan.blockSha256, motivation.juuretField)
    return HiskiQuery(
      queryId: queryId,
      eventType: eventType,
      requestedPrimaryName: requestedPrimary,
      requestedSecondaryName: requestedSecondary,
      requestedDate: requestedDate,
      parentBirthYear: parentBirthYear,
      queryPrimaryName: primary,
      querySecondaryName: secondary,
      queryDate: queryDate,
      searchURL: url.absoluteString,
      motivation: motivation
    )
  }

  public func parseSavedResults(_ html: String, for query: HiskiQuery) -> HiskiSearchResult {
    HiskiSearchResult(
      query: query,
      candidates: HiskiHTMLParser.resultCandidates(
        from: html, eventType: query.eventType, matchingDate: query.queryDate),
      responseSha256: sha256(html)
    )
  }

  public func search(_ query: HiskiQuery, allowLiveNetwork: Bool) async throws -> HiskiSearchResult {
    guard allowLiveNetwork else { throw HiskiResearchServiceError.liveNetworkApprovalRequired }
    let expected = try buildQuery(
      eventType: query.eventType, primaryName: query.requestedPrimaryName,
      secondaryName: query.requestedSecondaryName, date: query.requestedDate,
      parentBirthYear: query.parentBirthYear, motivation: query.motivation)
    guard expected == query else {
      throw HiskiResearchServiceError.invalidRequest("query fields do not match its deterministic query id")
    }
    guard let url = validatedHiskiURL(query.searchURL) else {
      throw HiskiResearchServiceError.invalidURL
    }
    return parseSavedResults(try await fetcher.html(from: url), for: query)
  }

  public func record(
    for candidate: HiskiResultCandidate,
    query: HiskiQuery,
    allowLiveNetwork: Bool
  ) async throws -> HiskiRecord {
    guard allowLiveNetwork else { throw HiskiResearchServiceError.liveNetworkApprovalRequired }
    let expectedQuery = try buildQuery(
      eventType: query.eventType, primaryName: query.requestedPrimaryName,
      secondaryName: query.requestedSecondaryName, date: query.requestedDate,
      parentBirthYear: query.parentBirthYear, motivation: query.motivation)
    guard expectedQuery == query, candidate.eventType == query.eventType else {
      throw HiskiResearchServiceError.invalidRequest(
        "candidate and query do not form a valid deterministic HiSki request")
    }
    guard candidate.recordURL == "https://hiski.genealogia.fi\(candidate.recordPath)",
      isDetailPath(candidate.recordPath, eventType: candidate.eventType)
    else {
      throw HiskiResearchServiceError.invalidRequest(
        "candidate is not a canonical sl.gif detail-record target")
    }
    guard let url = validatedHiskiURL(candidate.recordURL) else {
      throw HiskiResearchServiceError.invalidURL
    }
    let html = try await fetcher.html(from: url)
    guard let citationURL = HiskiHTMLParser.citationURL(fromRecordHTML: html) else {
      throw HiskiResearchServiceError.citationLinkMissing
    }
    return HiskiRecord(
      query: query,
      candidate: candidate,
      citationURL: citationURL,
      fields: HiskiHTMLParser.recordFields(from: html),
      recordText: HiskiHTMLParser.visibleText(from: html),
      responseSha256: sha256(html)
    )
  }

  private func validatedHiskiURL(_ raw: String) -> URL? {
    guard let url = URL(string: raw), url.scheme == "https",
      url.host?.lowercased() == "hiski.genealogia.fi", url.path == "/hiski"
    else { return nil }
    return url
  }

  private func isDetailPath(_ path: String, eventType: HiskiEventType) -> Bool {
    let escapedRegister = NSRegularExpression.escapedPattern(for: eventType.registerName)
    let pattern = "^/hiski\\?[a-z]{2}\\+\\d{4}\\+\(escapedRegister)\\+\\d+$"
    return path.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private func sha256(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

private func stableID(_ parts: String...) -> String {
  let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
    .map { String(format: "%02x", $0) }.joined()
  return "\(parts[0])-\(digest.prefix(24))"
}
