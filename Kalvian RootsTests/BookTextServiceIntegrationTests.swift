import Foundation
import XCTest
@testable import Kalvian_Roots

@MainActor
final class BookTextServiceIntegrationTests: XCTestCase {
    func testRootsFileManagerUsesExactCoreExtraction() async throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appendingPathComponent("JuuretKälviällä.roots")
        let source = """
        canonical

        TEST 1, pages 10,11
        Person <9DS5-XQ4>

        Note after an interior blank line.

        TEST 10, page 12
        Different family

        """
        try Data(source.utf8).write(to: sourceURL)
        let manager = RootsFileManager(documentsDirectory: directory)

        _ = try await manager.loadFile(from: sourceURL)
        let extracted = try XCTUnwrap(manager.extractFamilyText(familyId: " test   1 "))

        XCTAssertEqual(
            extracted,
            "TEST 1, pages 10,11\nPerson <9DS5-XQ4>\n\nNote after an interior blank line.\n"
        )
        XCTAssertFalse(extracted.contains("TEST 10"))
    }

    func testExplicitSelectionDoesNotReplaceDocumentsCanonicalSource() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let selectedDirectory = try makeTemporaryDirectory()
        let canonicalURL = documentsDirectory.appendingPathComponent("JuuretKälviällä.roots")
        let selectedURL = selectedDirectory.appendingPathComponent("JuuretKälviällä.roots")
        let canonicalData = Data("canonical\n\nORIGINAL 1, page 1\nOriginal\n".utf8)
        let selectedData = Data("canonical\n\nSELECTED 1, page 2\nSelected\n".utf8)
        try canonicalData.write(to: canonicalURL)
        try selectedData.write(to: selectedURL)
        let manager = RootsFileManager(documentsDirectory: documentsDirectory)

        _ = try await manager.loadFile(from: selectedURL)

        XCTAssertEqual(try Data(contentsOf: canonicalURL), canonicalData)
        XCTAssertEqual(try Data(contentsOf: selectedURL), selectedData)
        XCTAssertNotNil(manager.extractFamilyText(familyId: "SELECTED 1"))
        XCTAssertNil(manager.extractFamilyText(familyId: "ORIGINAL 1"))
    }

    func testAutoLoadUsesConfiguredDocumentsSource() async throws {
        let documentsDirectory = try makeTemporaryDirectory()
        let sourceURL = documentsDirectory.appendingPathComponent("JuuretKälviällä.roots")
        try Data("canonical\n\nAUTO 1, page 3\nLoaded\n".utf8).write(to: sourceURL)
        let manager = RootsFileManager(documentsDirectory: documentsDirectory)

        await manager.autoLoadDefaultFile()

        XCTAssertTrue(manager.isFileLoaded)
        XCTAssertEqual(manager.currentFileURL, sourceURL)
        XCTAssertEqual(manager.extractFamilyText(familyId: "AUTO 1"), "AUTO 1, page 3\nLoaded\n")
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
}
