import CryptoKit
import Foundation
import XCTest

@testable import KalvianRootsCore

final class BookTextServiceTests: XCTestCase {
  private let fixedDate = Date(timeIntervalSince1970: 0)

  func testSakeri4MatchesExactSavedSourceFixture() async throws {
    let sourceURL = try fixtureURL("JuuretKälviällä", extension: "roots")
    let expectedURL = try fixtureURL("SAKERI 4", extension: "txt")
    let service = makeService(sourceURL: sourceURL)

    let record = try await service.getFamilyText(
      familyId: "  sakeri   4  ",
      expectedSourceSHA256: nil
    )

    XCTAssertEqual(record.familyId, "SAKERI 4")
    XCTAssertEqual(record.rawText, try String(contentsOf: expectedURL, encoding: .utf8))
    XCTAssertEqual(record.span.pageReferences, ["265", "266"])
    XCTAssertEqual(record.span.startLine, 14)
    XCTAssertEqual(record.span.endLine, 27)
    XCTAssertEqual(record.source.loadedAt, "1970-01-01T00:00:00.000Z")
    XCTAssertEqual(
      Array(record.source.fileName.utf8),
      Array(canonicalRootsFileName.utf8),
      "The response must use the schema's canonical NFC filename literal"
    )
    XCTAssertTrue(record.rawText.contains("<KN1X-VHG>"))
    XCTAssertFalse(record.rawText.contains("SAKERI 40"))
    XCTAssertFalse(record.rawText.contains("\n#"))
  }

  func testPuukangas6MatchesExactSavedSourceFixture() async throws {
    let sourceURL = try fixtureURL("JuuretKälviällä", extension: "roots")
    let expectedURL = try fixtureURL("PUUKANGAS 6", extension: "txt")
    let service = makeService(sourceURL: sourceURL)

    let record = try await service.getFamilyText(
      familyId: "PUUKANGAS 6",
      expectedSourceSHA256: nil
    )

    XCTAssertEqual(record.familyId, "PUUKANGAS 6")
    XCTAssertEqual(record.rawText, try String(contentsOf: expectedURL, encoding: .utf8))
    XCTAssertEqual(record.span.pageReferences, ["204"])
    XCTAssertEqual(record.span.startLine, 3)
    XCTAssertEqual(record.span.endLine, 11)
    XCTAssertTrue(record.rawText.contains("<GL54-BJZ>"))
  }

  func testLocalCanonicalSourceMatchesSavedFixturesWhenAvailable() async throws {
    guard
      let documentsDirectory = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      ).first
    else {
      throw XCTSkip("Local Documents directory is unavailable")
    }
    let sourceURL = documentsDirectory.appendingPathComponent(canonicalRootsFileName)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw XCTSkip("The local canonical Juuret source is unavailable")
    }

    let service = BookTextService(
      locator: DocumentsBookSourceLocator(documentsDirectory: documentsDirectory),
      now: { Date(timeIntervalSince1970: 0) }
    )
    let puukangas = try await service.getFamilyText(
      familyId: "PUUKANGAS 6",
      expectedSourceSHA256: nil
    )
    let sakeri = try await service.getFamilyText(
      familyId: "SAKERI 4",
      expectedSourceSHA256: puukangas.source.sha256
    )

    XCTAssertEqual(
      puukangas.rawText,
      try String(
        contentsOf: fixtureURL("PUUKANGAS 6", extension: "txt"),
        encoding: .utf8
      )
    )
    XCTAssertEqual(
      sakeri.rawText,
      try String(
        contentsOf: fixtureURL("SAKERI 4", extension: "txt"),
        encoding: .utf8
      )
    )
    // Approved edits to other blocks can move these unchanged families and
    // change the whole-file hash. Validate spans against the current bytes.
    let currentData = try Data(contentsOf: sourceURL)
    let currentHash = SHA256.hash(data: currentData).map { String(format: "%02x", $0) }.joined()
    let lines = String(decoding: currentData, as: UTF8.self).components(separatedBy: "\n")
    for record in [puukangas, sakeri] {
      XCTAssertEqual(record.source.sha256, currentHash)
      XCTAssertEqual(record.span.sourceSha256, currentHash)
      let actualLines = lines[(record.span.startLine - 1)...(record.span.endLine - 1)]
        .joined(separator: "\n").trimmingCharacters(in: .newlines)
      XCTAssertEqual(actualLines, record.rawText.trimmingCharacters(in: .newlines))
    }
  }

  func testSourceAndBlockRevisionsAreExactAndStable() async throws {
    let sourceURL = try fixtureURL("JuuretKälviällä", extension: "roots")
    let originalData = try Data(contentsOf: sourceURL)
    let service = makeService(sourceURL: sourceURL)

    let revision = try await service.loadSource()
    let record = try await service.getFamilyText(
      familyId: "SAKERI 4",
      expectedSourceSHA256: revision.sha256
    )

    XCTAssertEqual(revision.fileName, canonicalRootsFileName)
    XCTAssertEqual(revision.byteCount, originalData.count)
    XCTAssertEqual(revision.sha256, record.span.sourceSha256)
    XCTAssertEqual(revision.sourceId, record.span.sourceId)
    XCTAssertEqual(record.span.blockSha256, sha256(Data(record.rawText.utf8)))
    XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
  }

  func testExactIdentifierBoundaryDoesNotReturnLongerIdentifier() async throws {
    let service = makeService(
      sourceURL: try fixtureURL("JuuretKälviällä", extension: "roots")
    )

    let shorter = try await service.getFamilyText(
      familyId: "SAKERI 4",
      expectedSourceSHA256: nil
    )
    let longer = try await service.getFamilyText(
      familyId: "SAKERI 40",
      expectedSourceSHA256: nil
    )

    XCTAssertTrue(shorter.rawText.hasPrefix("SAKERI 4,"))
    XCTAssertTrue(longer.rawText.hasPrefix("SAKERI 40,"))
    XCTAssertFalse(shorter.rawText.contains("synthetic boundary"))
    XCTAssertTrue(longer.rawText.contains("synthetic boundary"))
  }

  func testLetterSuffixedIdentifierHasAnExactBoundary() async throws {
    let sourceURL = try temporarySource(
      containing: "canonical\n\nMIEKKOJA 1, page 1\nFirst\n\nMIEKKOJA 1B, page 2\nSecond\n"
    )
    let service = makeService(sourceURL: sourceURL)

    let base = try await service.getFamilyText(
      familyId: "MIEKKOJA 1",
      expectedSourceSHA256: nil
    )
    let suffixed = try await service.getFamilyText(
      familyId: "miekkoja 1b",
      expectedSourceSHA256: nil
    )

    XCTAssertEqual(base.rawText, "MIEKKOJA 1, page 1\nFirst\n")
    XCTAssertEqual(suffixed.familyId, "MIEKKOJA 1B")
    XCTAssertEqual(suffixed.rawText, "MIEKKOJA 1B, page 2\nSecond\n")
  }

  func testMalformedIdentifierIsRejectedSeparatelyFromMissingFamily() async throws {
    let service = makeService(
      sourceURL: try fixtureURL("JuuretKälviällä", extension: "roots")
    )

    do {
      _ = try await service.getFamilyText(
        familyId: "SAKERI",
        expectedSourceSHA256: nil
      )
      XCTFail("Expected an invalid-family-identifier error")
    } catch let error as BookTextError {
      XCTAssertEqual(error.code, "invalid_family_identifier")
    }

    do {
      _ = try await service.getFamilyText(
        familyId: "SAKERI 9",
        expectedSourceSHA256: nil
      )
      XCTFail("Expected a family-not-found error")
    } catch let error as BookTextError {
      XCTAssertEqual(error, .familyNotFound("SAKERI 9"))
      XCTAssertEqual(error.code, "family_not_found")
    }
  }

  func testUnavailableSourceIsReported() async throws {
    let directory = try makeTemporaryDirectory()
    let missingURL = directory.appendingPathComponent(canonicalRootsFileName)
    let service = makeService(sourceURL: missingURL)

    do {
      _ = try await service.loadSource()
      XCTFail("Expected source-not-configured")
    } catch let error as BookTextError {
      XCTAssertEqual(error, .sourceNotConfigured)
    }
  }

  func testExplicitSourceIdentifierIsStableAndDoesNotExposeThePath() throws {
    let sourceURL = try fixtureURL("JuuretKälviällä", extension: "roots")

    let first = ExplicitBookSourceLocator.sourceId(for: sourceURL)
    let second = ExplicitBookSourceLocator.sourceId(for: sourceURL)

    XCTAssertEqual(first, second)
    XCTAssertTrue(first.hasPrefix("explicit-selection:"))
    XCTAssertFalse(first.contains(sourceURL.path))
  }

  func testWrongCanonicalMarkerIsRejected() async throws {
    let sourceURL = try temporarySource(containing: "not canonical\n\nTEST 1, page 1\nText\n")
    let service = makeService(sourceURL: sourceURL)

    do {
      _ = try await service.loadSource()
      XCTFail("Expected source-unreadable")
    } catch let error as BookTextError {
      XCTAssertEqual(error.code, "source_unreadable")
    }
  }

  func testUnreadableSourceIsReportedWithoutFallback() async throws {
    let sourceURL = try fixtureURL("JuuretKälviällä", extension: "roots")
    let timestamp = fixedDate
    let service = BookTextService(
      locator: ExplicitBookSourceLocator(url: sourceURL),
      reader: FailingReader(),
      now: { timestamp }
    )

    do {
      _ = try await service.loadSource()
      XCTFail("Expected source-unreadable")
    } catch let error as BookTextError {
      XCTAssertEqual(error.code, "source_unreadable")
    }
  }

  func testExpectedSourceHashDetectsChangedFile() async throws {
    let fixture = try fixtureURL("JuuretKälviällä", extension: "roots")
    let sourceURL = try copyToTemporaryCanonicalSource(fixture)
    let service = makeService(sourceURL: sourceURL)
    let originalRevision = try await service.loadSource()

    var changedData = try Data(contentsOf: sourceURL)
    changedData.append(Data("\n".utf8))
    try changedData.write(to: sourceURL, options: .atomic)

    do {
      _ = try await service.getFamilyText(
        familyId: "SAKERI 4",
        expectedSourceSHA256: originalRevision.sha256
      )
      XCTFail("Expected source-changed")
    } catch let error as BookTextError {
      XCTAssertEqual(error.code, "source_changed")
      guard case .sourceChanged(let expected, let actual) = error else {
        return XCTFail("Expected sourceChanged details")
      }
      XCTAssertEqual(expected, originalRevision.sha256)
      XCTAssertNotEqual(actual, originalRevision.sha256)
    }
  }

  func testUnexpectedFileNameAndInvalidUTF8AreRejected() async throws {
    let directory = try makeTemporaryDirectory()
    let wrongNameURL = directory.appendingPathComponent("Other.roots")
    try Data("canonical\n".utf8).write(to: wrongNameURL)

    do {
      _ = try await makeService(sourceURL: wrongNameURL).loadSource()
      XCTFail("Expected wrong file name to fail")
    } catch let error as BookTextError {
      XCTAssertEqual(error.code, "source_unreadable")
    }

    let invalidURL = directory.appendingPathComponent(canonicalRootsFileName)
    try Data([0xFF, 0xFE]).write(to: invalidURL)
    do {
      _ = try await makeService(sourceURL: invalidURL).loadSource()
      XCTFail("Expected invalid UTF-8 to fail")
    } catch let error as BookTextError {
      XCTAssertEqual(error.code, "source_unreadable")
    }
  }

  func testOversizedFamilyBlockFailsInsteadOfTruncating() async throws {
    let oversizedText = String(
      repeating: "A",
      count: BookTextService.maximumFamilyBlockBytes
    )
    let sourceURL = try temporarySource(
      containing: "canonical\n\nTEST 1, page 1\n\(oversizedText)\n"
    )

    do {
      _ = try await makeService(sourceURL: sourceURL).getFamilyText(
        familyId: "TEST 1",
        expectedSourceSHA256: nil
      )
      XCTFail("Expected resource-limit-exceeded")
    } catch let error as BookTextError {
      XCTAssertEqual(error.code, "resource_limit_exceeded")
      guard case .resourceLimitExceeded(let actual, let limit) = error else {
        return XCTFail("Expected resource limit details")
      }
      XCTAssertGreaterThan(actual, limit)
      XCTAssertEqual(limit, 65_536)
    }
  }

  func testCRLFAndInteriorBlankLinesArePreservedExactly() async throws {
    let text =
      "canonical\r\n\r\nTEST 1, page 8\r\nFirst\r\n\r\nSecond <9DS5-XQ4>\r\n\r\nTEST 2, page 9\r\nNext\r\n"
    let sourceURL = try temporarySource(data: Data(text.utf8))

    let record = try await makeService(sourceURL: sourceURL).getFamilyText(
      familyId: "TEST 1",
      expectedSourceSHA256: nil
    )

    XCTAssertEqual(
      record.rawText,
      "TEST 1, page 8\r\nFirst\r\n\r\nSecond <9DS5-XQ4>\r\n"
    )
    XCTAssertEqual(record.span.startLine, 3)
    XCTAssertEqual(record.span.endLine, 6)
  }

  func testDuplicateFamilyHeadersAreReportedRatherThanGuessed() async throws {
    let sourceURL = try temporarySource(
      containing: "canonical\n\nTEST 1, page 1\nFirst\n\nTEST 1, page 2\nSecond\n"
    )

    do {
      _ = try await makeService(sourceURL: sourceURL).getFamilyText(
        familyId: "TEST 1",
        expectedSourceSHA256: nil
      )
      XCTFail("Expected duplicate family headers to fail")
    } catch let error as BookTextError {
      XCTAssertEqual(error.code, "source_unreadable")
    }
  }

  private func makeService(sourceURL: URL) -> BookTextService {
    let timestamp = fixedDate
    return BookTextService(
      locator: ExplicitBookSourceLocator(url: sourceURL, sourceId: "test-source"),
      now: { timestamp }
    )
  }

  private func fixtureURL(_ name: String, extension fileExtension: String) throws -> URL {
    let url = try XCTUnwrap(Bundle.module.resourceURL)
      .appendingPathComponent("Fixtures", isDirectory: true)
      .appendingPathComponent(name)
      .appendingPathExtension(fileExtension)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    return url
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }
    return directory
  }

  private func temporarySource(containing text: String) throws -> URL {
    try temporarySource(data: Data(text.utf8))
  }

  private func temporarySource(data: Data) throws -> URL {
    let directory = try makeTemporaryDirectory()
    let url = directory.appendingPathComponent(canonicalRootsFileName)
    try data.write(to: url)
    return url
  }

  private func copyToTemporaryCanonicalSource(_ source: URL) throws -> URL {
    try temporarySource(data: Data(contentsOf: source))
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct FailingReader: BookDataReading {
  struct Failure: Error {}

  func readData(from url: URL) throws -> Data {
    throw Failure()
  }
}
