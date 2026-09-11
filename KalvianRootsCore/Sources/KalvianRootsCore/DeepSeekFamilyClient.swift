import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol DeepSeekCredentialProviding: Sendable {
  func apiKey() throws -> String
}

public struct LocalDeepSeekCredentialProvider: DeepSeekCredentialProviding, @unchecked Sendable {
  private let defaults: UserDefaults
  private let appDefaults: UserDefaults?
  private let environment: [String: String]

  public init(
    defaults: UserDefaults = .standard,
    appDefaults: UserDefaults? = UserDefaults(suiteName: "com.michael-bendio.Kalvian-Roots"),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.defaults = defaults
    self.appDefaults = appDefaults
    self.environment = environment
  }

  public func apiKey() throws -> String {
    if let key = defaults.string(forKey: "AIService_DeepSeek_APIKey"), !key.isEmpty { return key }
    if let key = appDefaults?.string(forKey: "AIService_DeepSeek_APIKey"), !key.isEmpty { return key }
    if let key = environment["DEEPSEEK_API_KEY"], !key.isEmpty { return key }
    throw FamilyParsingError.credentialUnavailable
  }
}

public struct DeepSeekFamilyClient: FamilyAIResponding {
  private let credentials: any DeepSeekCredentialProviding
  private let session: URLSession
  private let endpoint = URL(string: "https://api.deepseek.com/v1/chat/completions")!

  public init(
    credentials: any DeepSeekCredentialProviding = LocalDeepSeekCredentialProvider(),
    session: URLSession = .shared
  ) {
    self.credentials = credentials
    self.session = session
  }

  public func parseFamily(familyId: String, familyText: String) async throws -> String {
    let key = try credentials.apiKey()
    let body: [String: Any] = [
      "model": "deepseek-chat",
      "messages": [
        ["role": "system", "content": "You are a Finnish genealogy data extraction expert. Return only valid JSON."],
        ["role": "user", "content": DeepSeekFamilyPrompt.make(familyId: familyId, familyText: familyText)],
      ],
      "temperature": 0.1,
      "max_tokens": 4000,
    ]
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw FamilyParsingError.aiRequestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
      }
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let choices = root["choices"] as? [[String: Any]],
        let message = choices.first?["message"] as? [String: Any],
        let content = message["content"] as? String
      else { throw FamilyParsingError.aiRequestFailed("Response has no message content.") }
      return content
    } catch let error as FamilyParsingError { throw error }
    catch { throw FamilyParsingError.aiRequestFailed(error.localizedDescription) }
  }
}

public enum DeepSeekFamilyPrompt {
  public static func make(familyId: String, familyText: String) -> String {
    """
    Parse only family \(familyId) and return ONLY one valid JSON object. Do not use markdown.
    Set "schemaVersion" to "\(juuretFamilySchemaVersion)".

    Required shape:
    {
      "schemaVersion":"\(juuretFamilySchemaVersion)",
      "familyId":"string",
      "pageReferences":["string"],
      "couples":[{
        "husband": PERSON,
        "wife": PERSON,
        "marriageDate":"string or null",
        "fullMarriageDate":"string or null",
        "children":[PERSON],
        "childrenDiedInfancy":"integer or null",
        "coupleNotes":["string"]
      }],
      "notes":["string"],
      "noteDefinitions":{"*":"exact note text"}
    }

    PERSON fields are name, patronymic, birthDate, deathDate, marriageDate,
    fullMarriageDate, spouse, asChild, asParent, familySearchId,
    spouseFamilySearchId, noteMarkers, fatherName, motherName,
    spouseBirthDate, and spouseParentsFamilyId. Optional values may be null;
    noteMarkers must always be an array.

    Parent relationships are represented by the couple. Leave their child-only
    spouse, spouseFamilySearchId, spouseBirthDate, and spouseParentsFamilyId fields null.
    Each ★ starts a new person row. A date belongs only to that same row;
    a blank birth date must stay null and must not borrow the next row's date.
    The name field contains the given name only; put the exact patronymic token
    (for example Laurinp., Juhonp., Antint.) in patronymic, without expansion.
    pageReferences contains only page numbers, for example ["237", "239"],
    never the words "page" or "pages". Family references contain the identifier
    without surrounding braces. Retain trailing family references on child rows
    as asParent even when they are not enclosed in braces.
    A spouse lifespan such as "1711-1792" is not a marriage date: put only the
    birth part in spouseBirthDate and preserve the lifespan in a note.
    Do not invent a note definition when the source has a marker but no definition.

    Preserve every name, patronymic, spelling, punctuation, and date exactly.
    Never normalize or translate names. Preserve approximate "n " prefixes.
    Preserve historical death expressions such as "isoviha" exactly.
    Put a two-digit marriage year (including "n 30") in marriageDate; put a
    complete date or approximate four-digit year (including "n 1730") in
    fullMarriageDate.
    Curly-brace references on parents are asChild; references on married children
    are asParent. Angle-bracket IDs are FamilySearch progress annotations and go
    only in familySearchId or spouseFamilySearchId; they are not book facts.
    Keep child and spouse IDs separate. Strip marriage-number prefixes such as
    "1. " from spouse names. Store note markers as asterisks without ")".
    Match trailing person markers such as "*)" and "**)" to definitions after
    the children. Remove the marker prefix from definition text, but preserve
    the remaining note text, dates, and punctuation exactly.
    Ignore origin phrases beginning "synt." rather than putting them in facts or notes.
    Create an "Unknown" PERSON object when one member of a parental couple is absent;
    never return a null husband or wife. Create one couple per marriage and keep each
    couple's children grouped with that couple. Treat "II puoliso" and
    "III puoliso" as additional marriages; repeat the surviving parent in each
    applicable couple and attach each Lapset section only to the couple above it.

    Exact source block:
    \(familyText)
    """
  }
}
