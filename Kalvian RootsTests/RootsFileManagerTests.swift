//
//
//  RootsFileManagerTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for RootsFileManager
//

import XCTest
@testable import Kalvian_Roots

@MainActor
final class RootsFileManagerTests: XCTestCase {
    
    var fileManager: RootsFileManager!
    private var temporaryDocumentsDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        temporaryDocumentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RootsFileManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDocumentsDirectory,
            withIntermediateDirectories: true
        )

        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../KalvianRootsCore/Tests/KalvianRootsCoreTests/Fixtures/JuuretKälviällä.roots")
            .standardizedFileURL
        let canonicalURL = temporaryDocumentsDirectory
            .appendingPathComponent("JuuretKälviällä.roots")
        try FileManager.default.copyItem(at: fixtureURL, to: canonicalURL)

        fileManager = RootsFileManager(documentsDirectory: temporaryDocumentsDirectory)
        await fileManager.autoLoadDefaultFile()
        XCTAssertTrue(fileManager.isFileLoaded, fileManager.errorMessage ?? "Fixture did not load")
    }
    
    override func tearDown() async throws {
        fileManager = nil
        if let temporaryDocumentsDirectory {
            try? FileManager.default.removeItem(at: temporaryDocumentsDirectory)
        }
        temporaryDocumentsDirectory = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testFileManagerInitialization() {
        XCTAssertNotNil(fileManager, "File manager should initialize")
    }
    
    // MARK: - File Loading Tests
    
    func testFilePathIsValid() async throws {
        // Then: Should have valid file URL
        let url = try XCTUnwrap(fileManager.currentFileURL)
        XCTAssertFalse(url.path.isEmpty, "File path should not be empty")
        XCTAssertEqual(url.lastPathComponent, "JuuretKälviällä.roots")
    }
    
    // MARK: - Family Extraction Tests
    
    // MARK: - Get All Family IDs Tests
    
    func testGetAllFamilyIds() async {
        // When: Getting all family IDs
        let familyIds = fileManager.getAllFamilyIds()
        
        // Then: Should return array of IDs
        XCTAssertGreaterThan(familyIds.count, 0, "Should have family IDs")
        XCTAssertTrue(familyIds.contains("KORPI 6"), "Should contain known family")
    }
    
    func testGetAllFamilyIdsOrder() async {
        // When: Getting all family IDs
        let familyIds = fileManager.getAllFamilyIds()
        
        // Then: Should be in file order
        XCTAssertGreaterThan(familyIds.count, 1, "Should have multiple families")
    }
    
    func testGetAllFamilyIdsBeforeFileLoads() {
        // Given: A manager that has not explicitly loaded its source
        let unloadedManager = RootsFileManager(documentsDirectory: temporaryDocumentsDirectory)
        
        // Then: The static family index remains available without loading source text
        XCTAssertFalse(unloadedManager.isFileLoaded)
        XCTAssertFalse(unloadedManager.getAllFamilyIds().isEmpty)
    }
    
    // MARK: - File Search Tests
    
    func testFindFamilyInFile() async {
        // When: Finding a family
        let found = fileManager.familyExistsInFile("KORPI 6")
        
        // Then: Should find it
        XCTAssertTrue(found, "Should find existing family")
    }
    
    func testFamilyNotInFile() async {
        // When: Looking for non-existent family
        let found = fileManager.familyExistsInFile("NONEXISTENT 999")
        
        // Then: Should not find it
        XCTAssertFalse(found, "Should not find non-existent family")
    }
    
    func testCaseInsensitiveSearch() async {
        // When: Searching with different cases
        let upper = fileManager.familyExistsInFile("KORPI 6")
        let lower = fileManager.familyExistsInFile("korpi 6")
        
        // Then: Should find both
        XCTAssertEqual(upper, lower, "Search should be case-insensitive")
    }
    
    // MARK: - File State Tests
    
    func testCurrentFileURLProperty() async {
        // Then: Should have file URL
        XCTAssertEqual(fileManager.currentFileURL?.deletingLastPathComponent(), temporaryDocumentsDirectory)
    }
    
    func testCurrentFileContentProperty() async throws {
        // Then: Should have contents
        let contents = try XCTUnwrap(fileManager.currentFileContent)
        XCTAssertGreaterThan(contents.count, 1000, "Fixture should have substantial content")
    }
    
    // MARK: - Error Handling Tests
    
    func testHandleMissingFile() {
        // Test: Should handle when canonical file doesn't exist
        // (Would require testing with missing file)
    }
    
    func testHandleFilePermissionError() {
        // Test: Should handle when file can't be read
    }
    
    func testHandleCorruptedFile() {
        // Test: Should handle when file is corrupted
    }
    
    // MARK: - Local Documents Tests
    
    func testUsesConfiguredLocalDocumentsDirectory() async {
        XCTAssertEqual(
            fileManager.currentFileURL?.deletingLastPathComponent(),
            temporaryDocumentsDirectory
        )
    }
    
    func testHandlesICloudUnavailable() {
        // Test: Should handle when iCloud is not available
    }
    
    // MARK: - Concurrent Access Tests
    
    // MARK: - Performance Tests
    
    func testExtractionPerformance() async {
        // When: Measuring extraction time
        let startTime = Date()
        let familyText = fileManager.extractFamilyText(familyId: "SAKERI 4")
        let endTime = Date()
        
        // Then: Should be fast
        XCTAssertNotNil(familyText)
        let duration = endTime.timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 1.0, "Extraction should be fast")
    }
}
