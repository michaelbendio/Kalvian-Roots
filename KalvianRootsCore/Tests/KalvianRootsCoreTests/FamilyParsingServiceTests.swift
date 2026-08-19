import Foundation
import XCTest
@testable import KalvianRootsCore

final class FamilyParsingServiceTests: XCTestCase {
  func testSavedFamilyFixturesDecode() throws {
    let sakeri = try FamilyJSONDecoder.decode(try fixture("SAKERI 4.json"), expectedFamilyId: "SAKERI 4")
    let difficult = try FamilyJSONDecoder.decode(try fixture("HYYPPA 7.json"), expectedFamilyId: "HYYPPÄ 7")
    XCTAssertEqual(sakeri.primaryCouple?.children.first?.familySearchId, "KN1X-VHG")
    XCTAssertEqual(difficult.couples.count, 2)
  }

  func testDecoderPreservesExactNamesPatronymicsAndMultipleSpouses() throws {
    let family = try FamilyJSONDecoder.decode(Self.multipleSpouseJSON, expectedFamilyId: "HYYPPÄ 7")
    XCTAssertEqual(family.couples.count, 2)
    XCTAssertEqual(family.couples[0].husband.displayName, "Jaakko Jaakonp.")
    XCTAssertEqual(family.couples[0].wife.displayName, "Brita Antint.")
    XCTAssertEqual(family.couples[1].wife.name, "Elisabet")
    XCTAssertEqual(family.couples[0].children.map(\.name), ["Maria", "Maria"])
    XCTAssertEqual(family.couples[0].children.map(\.birthDate), ["01.01.1751", "02.02.1753"])
  }

  func testDecoderRejectsMalformedJSONAndUnsupportedSchema() {
    XCTAssertThrowsError(try FamilyJSONDecoder.decode("{bad", expectedFamilyId: "SAKERI 4")) {
      guard case FamilyParsingError.malformedAIResponse = $0 else { return XCTFail("Unexpected \($0)") }
    }
    XCTAssertThrowsError(try FamilyJSONDecoder.decode(
      Self.multipleSpouseJSON.replacingOccurrences(of: "juuret-family/1", with: "juuret-family/99"),
      expectedFamilyId: "HYYPPÄ 7"
    )) {
      XCTAssertEqual($0 as? FamilyParsingError, .unsupportedSchema("juuret-family/99"))
    }
    XCTAssertThrowsError(try FamilyJSONDecoder.decode(
      Self.multipleSpouseJSON.replacingOccurrences(
        of: #""familyId":"HYYPPÄ 7""#,
        with: #""familyId":"HYYPPÄ 7","inventedField":"value""#
      ),
      expectedFamilyId: "HYYPPÄ 7"
    )) {
      guard case FamilyParsingError.validationFailed = $0 else {
        return XCTFail("Unexpected \($0)")
      }
    }
  }

  func testUsableSchema2LegacyEntryIsImportedWithoutCallingAI() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("families.json")
    let nativeURL = directory.appendingPathComponent("parsed.json")
    try Self.legacyPayload(mainFamilyJSON: Self.sakeriFamilyJSON).write(to: legacyURL)
    let ai = CountingAI(response: "not used")
    let service = FamilyParsingService(
      ai: ai,
      nativeCache: NativeParsedFamilyCache(url: nativeURL),
      legacyCache: LegacyFamilyCacheReader(url: legacyURL)
    )
    let source = try sourceRecord(familyId: "SAKERI 4", pages: ["265", "266"])

    let record = try await service.parseFamily(source: source, cachePolicy: .useValidated)

    XCTAssertEqual(record.parsedFamily.primaryCouple?.husband.displayName, "Antti Mikonp.")
    XCTAssertEqual(record.parserImplementationVersion, "legacy-schema2-unknown")
    XCTAssertEqual(record.warnings.map(\.code), ["legacy_cache_provenance_limited"])
    let callCount = await ai.calls
    let cached = try await service.getParsedFamily(
      familyId: "SAKERI 4", sourceSHA256: source.source.sha256
    )
    XCTAssertEqual(callCount, 0)
    XCTAssertNotNil(cached)
  }

  func testMalformedLegacyEntryIsRejectedAndDoesNotCallAI() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("families.json")
    let malformed: [String: Any] = [
      "schemaVersion": 2,
      "families": ["SAKERI 4": ["network": ["wrong": true]]],
    ]
    try JSONSerialization.data(withJSONObject: malformed).write(to: legacyURL)
    let ai = CountingAI(response: "not used")
    let service = FamilyParsingService(
      ai: ai,
      nativeCache: NativeParsedFamilyCache(url: directory.appendingPathComponent("native.json")),
      legacyCache: LegacyFamilyCacheReader(url: legacyURL)
    )

    do {
      _ = try await service.parseFamily(
        source: sourceRecord(familyId: "SAKERI 4", pages: ["265", "266"]),
        cachePolicy: .useValidated
      )
      XCTFail("Expected malformed legacy cache to fail")
    } catch let error as FamilyParsingError {
      guard case .cacheUnreadable = error else { return XCTFail("Unexpected \(error)") }
    }
    let callCount = await ai.calls
    XCTAssertEqual(callCount, 0)
  }

  func testCacheOnlyMissDoesNotCallAI() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ai = CountingAI(response: Self.multipleSpouseJSON)
    let service = FamilyParsingService(
      ai: ai,
      nativeCache: NativeParsedFamilyCache(url: directory.appendingPathComponent("native.json")),
      legacyCache: LegacyFamilyCacheReader(url: directory.appendingPathComponent("missing.json"))
    )
    do {
      _ = try await service.parseFamily(
        source: sourceRecord(familyId: "HYYPPÄ 7", pages: ["10"]),
        cachePolicy: .cacheOnly
      )
      XCTFail("Expected cache miss")
    } catch let error as FamilyParsingError {
      XCTAssertEqual(error, .cacheMiss("HYYPPÄ 7"))
    }
    let callCount = await ai.calls
    XCTAssertEqual(callCount, 0)
  }

  func testRefreshCallsAIAndChangedSourceHashInvalidatesNativeCache() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ai = CountingAI(response: Self.multipleSpouseJSON)
    let service = FamilyParsingService(
      ai: ai,
      nativeCache: NativeParsedFamilyCache(url: directory.appendingPathComponent("native.json")),
      legacyCache: LegacyFamilyCacheReader(url: directory.appendingPathComponent("missing.json"))
    )
    let source = try sourceRecord(familyId: "HYYPPÄ 7", pages: ["10"])
    _ = try await service.parseFamily(source: source, cachePolicy: .refresh)
    let callCount = await ai.calls
    let cached = try await service.getParsedFamily(
      familyId: "HYYPPÄ 7", sourceSHA256: source.source.sha256
    )
    let changed = try await service.getParsedFamily(
      familyId: "HYYPPÄ 7", sourceSHA256: String(repeating: "f", count: 64)
    )
    XCTAssertEqual(callCount, 1)
    XCTAssertNotNil(cached)
    XCTAssertNil(changed)
  }

  private func sourceRecord(familyId: String, pages: [String]) throws -> FamilyTextRecord {
    let raw = "\(familyId), page \(pages.joined(separator: ","))\nsource\n"
    let hash = String(repeating: "a", count: 64)
    return FamilyTextRecord(
      familyId: familyId,
      rawText: raw,
      source: SourceRevision(
        sourceId: "test", fileName: canonicalRootsFileName, sha256: hash,
        byteCount: raw.utf8.count, loadedAt: "2026-08-19T00:00:00.000Z", canonicalMarkerValid: true
      ),
      span: SourceSpan(
        sourceId: "test", sourceSha256: hash, familyId: familyId,
        pageReferences: pages, startLine: 1, endLine: 2,
        blockSha256: String(repeating: "b", count: 64)
      )
    )
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func fixture(_ name: String) throws -> String {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  private static func legacyPayload(mainFamilyJSON: String) throws -> Data {
    let family = try JSONSerialization.jsonObject(with: Data(mainFamilyJSON.utf8))
    return try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 2,
      "families": [
        "SAKERI 4": [
          "cachedAt": "2026-08-19T00:00:00Z", "extractionTime": 1,
          "network": ["mainFamily": family, "asChildFamilies": [:], "asParentFamilies": [:], "spouseAsChildFamilies": [:]],
        ]
      ],
    ])
  }

  private static let sakeriFamilyJSON = """
  {"familyId":"SAKERI 4","pageReferences":["265","266"],"couples":[{"husband":{"name":"Antti","patronymic":"Mikonp.","birthDate":"05.08.1729","noteMarkers":[]},"wife":{"name":"Brita","patronymic":"Juhont.","birthDate":"04.01.1735","noteMarkers":[]},"fullMarriageDate":"08.10.1750","children":[{"name":"Maria","birthDate":"03.03.1756","spouse":"Juho Styrman","asParent":"Puukangas 6","familySearchId":"KN1X-VHG","noteMarkers":[]}],"coupleNotes":[]}],"notes":[],"noteDefinitions":{}}
  """

  private static let multipleSpouseJSON = """
  {"schemaVersion":"juuret-family/1","familyId":"HYYPPÄ 7","pageReferences":["10"],"couples":[{"husband":{"name":"Jaakko","patronymic":"Jaakonp.","noteMarkers":[]},"wife":{"name":"Brita","patronymic":"Antint.","noteMarkers":[]},"children":[{"name":"Maria","birthDate":"01.01.1751","noteMarkers":[]},{"name":"Maria","birthDate":"02.02.1753","noteMarkers":[]}],"coupleNotes":[]},{"husband":{"name":"Jaakko","patronymic":"Jaakonp.","noteMarkers":[]},"wife":{"name":"Elisabet","patronymic":"Matint.","noteMarkers":[]},"children":[{"name":"Antti","birthDate":"03.03.1760","noteMarkers":[]}],"coupleNotes":[]}],"notes":[],"noteDefinitions":{}}
  """
}

private actor CountingAI: FamilyAIResponding {
  private(set) var calls = 0
  let response: String
  init(response: String) { self.response = response }
  func parseFamily(familyId: String, familyText: String) async throws -> String {
    calls += 1
    return response
  }
}
