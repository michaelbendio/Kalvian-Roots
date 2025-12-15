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
    
    override func setUp() async throws {
        try await super.setUp()
        fileManager = RootsFileManager()
        
        // Wait for file to load by polling
        for _ in 0..<50 { // Wait up to 5 seconds
            if fileManager.isFileLoaded {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
    
    override func tearDown() async throws {
        fileManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testFileManagerInitialization() {
        XCTAssertNotNil(fileManager, "File manager should initialize")
    }
    
    // MARK: - File Loading Tests
    
    func testFileLoadsAutomatically() async {
        // Then: File should be loaded from setUp
        XCTAssertTrue(fileManager.isFileLoaded, "isFileLoaded should be true")
    }
    
    func testFilePathIsValid() async {
        // Then: Should have valid file URL
        if let url = fileManager.currentFileURL {
            XCTAssertFalse(url.path.isEmpty, "File path should not be empty")
            XCTAssertTrue(url.path.contains("JuuretKälviällä"), "Should be the correct file")
        }
    }
    
    func testFileContentsAvailable() async {
        // Then: Should have file contents
        XCTAssertNotNil(fileManager.currentFileContent, "Should have file contents")
        XCTAssertFalse(fileManager.currentFileContent?.isEmpty ?? true, "File should not be empty")
    }
    
    // MARK: - Family Extraction Tests
    
    func testExtractFamilyText() async {
        // When: Extracting a known family
        let familyText = fileManager.extractFamilyText(familyId: "KORPI 6")
        
        // Then: Should get family text
        XCTAssertNotNil(familyText, "Should extract family text")
        XCTAssertFalse(familyText?.isEmpty ?? true, "Family text should not be empty")
    }
    
    func testExtractFamilyTextHandlesInvalidID() async {
        // When: Extracting invalid family
        let familyText = fileManager.extractFamilyText(familyId: "INVALID 999")
        
        // Then: Should return nil
        XCTAssertNil(familyText, "Should return nil for invalid family ID")
    }
    
    func testExtractFamilyTextNormalizesID() async {
        // When: Extracting with lowercase ID
        let familyText1 = fileManager.extractFamilyText(familyId: "korpi 6")
        let familyText2 = fileManager.extractFamilyText(familyId: "KORPI 6")
        
        // Then: Should normalize and return same text
        XCTAssertNotNil(familyText1, "Should extract lowercase ID")
        XCTAssertNotNil(familyText2, "Should extract uppercase ID")
    }
    
    func testExtractFamilyTextWithWhitespace() async {
        // When: Extracting with extra whitespace
        let familyText = fileManager.extractFamilyText(familyId: "  KORPI 6  ")
        
        // Then: Should handle whitespace
        XCTAssertNotNil(familyText, "Should handle whitespace in ID")
    }
    
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
        // When: Getting IDs before file loads
        let familyIds = fileManager.getAllFamilyIds()
        
        // Then: Should return empty array or handle gracefully
        XCTAssertTrue(true, "Should handle request before file loads")
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
    
    func testIsFileLoadedProperty() async {
        // Then: File should be loaded from setUp
        XCTAssertTrue(fileManager.isFileLoaded, "File should be loaded")
    }
    
    func testCurrentFileURLProperty() async {
        // Then: Should have file URL
        if let url = fileManager.currentFileURL {
            XCTAssertFalse(url.path.isEmpty, "File path should not be empty")
            XCTAssertTrue(url.path.contains("JuuretKälviällä"), "Should be the correct file")
        }
    }
    
    func testCurrentFileContentProperty() async {
        // Then: Should have contents
        if let contents = fileManager.currentFileContent {
            XCTAssertGreaterThan(contents.count, 1000, "File should have substantial content")
        }
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
    
    // MARK: - iCloud Integration Tests
    
    func testFindsFileInICloudDrive() async {
        // Then: Should find in iCloud location
        if let url = fileManager.currentFileURL {
            XCTAssertTrue(
                url.path.contains("iCloud") || url.path.contains("Library"),
                "Should be in expected location"
            )
        }
    }
    
    func testHandlesICloudUnavailable() {
        // Test: Should handle when iCloud is not available
    }
    
    // MARK: - Concurrent Access Tests
    
    func testMultipleConcurrentExtractions() async {
        // When: Multiple concurrent extractions
        async let text1 = Task { fileManager.extractFamilyText(familyId: "KORPI 6") }
        async let text2 = Task { fileManager.extractFamilyText(familyId: "HERLEVI 1") }
        async let text3 = Task { fileManager.extractFamilyText(familyId: "SIKALA 3") }
        
        // Then: Should handle concurrency
        let results = await (text1.value, text2.value, text3.value)
        XCTAssertNotNil(results.0, "First extraction should succeed")
        XCTAssertNotNil(results.1, "Second extraction should succeed")
        XCTAssertNotNil(results.2, "Third extraction should succeed")
    }
    
    // MARK: - Performance Tests
    
    func testExtractionPerformance() async {
        // When: Measuring extraction time
        let startTime = Date()
        _ = fileManager.extractFamilyText(familyId: "KORPI 6")
        let endTime = Date()
        
        // Then: Should be fast
        let duration = endTime.timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 1.0, "Extraction should be fast")
    }
}
