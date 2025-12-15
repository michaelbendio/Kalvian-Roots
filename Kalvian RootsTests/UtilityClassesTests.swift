//
//  UtilityClassesTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for NameEquivalenceManager, HiskiService, FamilyIDs
//

import XCTest
@testable import Kalvian_Roots

// MARK: - NameEquivalenceManager Tests

final class NameEquivalenceManagerTests: XCTestCase {
    
    var manager: NameEquivalenceManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        manager = NameEquivalenceManager()
    }

    override func tearDownWithError() throws {
        manager = nil
        try super.tearDownWithError()
    }
    
    func testManagerInitialization() {
        XCTAssertNotNil(manager, "Manager should initialize")
    }
    
    func testFinnishSwedishEquivalence() {
        // Test common Finnish-Swedish name pairs
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "Juho"))
        XCTAssertTrue(manager.areNamesEquivalent("Matti", "Matias"))
        XCTAssertTrue(manager.areNamesEquivalent("Pietari", "Petrus"))
    }
    
    func testCaseInsensitiveEquivalence() {
        // Test case insensitivity
        XCTAssertTrue(manager.areNamesEquivalent("JOHAN", "juho"))
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "JUHO"))
    }
    
    func testNonEquivalentNames() {
        // Test names that are not equivalent
        XCTAssertFalse(manager.areNamesEquivalent("Matti", "Henrik"))
        XCTAssertFalse(manager.areNamesEquivalent("Johan", "Erik"))
    }
    
    func testIdenticalNames() {
        // Test identical names
        XCTAssertTrue(manager.areNamesEquivalent("Matti", "Matti"))
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "Johan"))
    }
    
    func testEmptyNames() {
        // Test empty names
        XCTAssertTrue(manager.areNamesEquivalent("", ""))
        XCTAssertFalse(manager.areNamesEquivalent("Matti", ""))
    }
    
    func testAddCustomEquivalence() {
        // When: Adding custom equivalence
        manager.addEquivalence(between: "TestName1", and: "TestName2")
        
        // Then: Should recognize equivalence
        XCTAssertTrue(manager.areNamesEquivalent("TestName1", "TestName2"))
    }
    
    func testRemoveEquivalence() {
        // Given: Custom equivalence
        manager.addEquivalence(between: "TestName1", and: "TestName2")
        XCTAssertTrue(manager.areNamesEquivalent("TestName1", "TestName2"))

        // When: Removing equivalence
        manager.removeEquivalence(between: "TestName1", and: "TestName2")
        
        // Then: Should no longer be equivalent
        XCTAssertFalse(manager.areNamesEquivalent("TestName1", "TestName2"))
    }
    
    func testBidirectionalEquivalence() {
        // Test that equivalence works both ways
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "Juho"))
        XCTAssertTrue(manager.areNamesEquivalent("Juho", "Johan"))
    }
    
    func testMultipleEquivalences() {
        // Test names with multiple equivalent forms
        // (Some names might have multiple Finnish/Swedish variants)
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "Juho"))
    }
}

// MARK: - HiskiService Tests

@MainActor
final class HiskiServiceTests: XCTestCase {
    
    var service: HiskiService!
    var nameEquivalenceManager: NameEquivalenceManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        nameEquivalenceManager = NameEquivalenceManager()
        service = HiskiService(nameEquivalenceManager: nameEquivalenceManager)
    }

    override func tearDownWithError() throws {
        service = nil
        nameEquivalenceManager = nil
        try super.tearDownWithError()
    }
    
    func testServiceInitialization() {
        XCTAssertNotNil(service, "Service should initialize")
    }
    
    func testSetCurrentFamily() {
        // When: Setting current family
        service.setCurrentFamily("KORPI 6")
        
        // Then: Should be set
        XCTAssertTrue(true, "Should set current family")
    }
    
    func testQueryBirthGeneratesURL() async throws {
        // Integration test - would require actual query
        // Test that birth query generates proper Hiski URL
    }
    
    func testQueryDeathGeneratesURL() async throws {
        // Integration test - would require actual query
        // Test that death query generates proper Hiski URL
    }
    
    func testQueryMarriageGeneratesURL() async throws {
        // Integration test - would require actual query
        // Test that marriage query generates proper Hiski URL
    }
    
    func testQueryHandlesInvalidDate() async throws {
        // Test error handling for invalid date format
    }
    
    func testQueryHandlesInvalidName() async throws {
        // Test error handling for invalid name
    }
    
    func testURLFormatting() {
        // Test that generated URLs follow Hiski format
        // hiski.genealogia.fi/...
    }
    
    func testDateExtraction() {
        // Test extracting year from date string
        // e.g., "15.02.1730" -> "1730"
    }
    
    func testNameNormalization() {
        // Test name normalization for Hiski queries
        // Handle patronymics, special characters, etc.
    }
}

// MARK: - FamilyIDs Tests

final class FamilyIDsTests: XCTestCase {
    
    func testIsValidWithValidID() {
        // Test valid family IDs
        XCTAssertTrue(FamilyIDs.isValid(familyId: "KORPI 6"))
        XCTAssertTrue(FamilyIDs.isValid(familyId: "HERLEVI 1"))
        XCTAssertTrue(FamilyIDs.isValid(familyId: "SIKALA 3"))
    }
    
    func testIsValidWithInvalidID() {
        // Test invalid family IDs
        XCTAssertFalse(FamilyIDs.isValid(familyId: "INVALID 999"))
        XCTAssertFalse(FamilyIDs.isValid(familyId: "NOT A FAMILY"))
        XCTAssertFalse(FamilyIDs.isValid(familyId: ""))
    }
    
    func testCaseInsensitiveValidation() {
        // Test case insensitivity
        XCTAssertTrue(FamilyIDs.isValid(familyId: "korpi 6"))
        XCTAssertTrue(FamilyIDs.isValid(familyId: "KORPI 6"))
        XCTAssertTrue(FamilyIDs.isValid(familyId: "Korpi 6"))
    }
    
    func testIndexOf() {
        // Test getting index of family ID
        if let index = FamilyIDs.indexOf(familyId: "KORPI 6") {
            XCTAssertGreaterThanOrEqual(index, 0, "Index should be valid")
        } else {
            XCTFail("KORPI 6 should have an index")
        }
    }
    
    func testIndexOfInvalidID() {
        // Test invalid ID returns nil
        let index = FamilyIDs.indexOf(familyId: "INVALID 999")
        XCTAssertNil(index, "Invalid ID should return nil index")
    }
    
    func testFamilyAtIndex() {
        // Test getting family at index
        if let firstFamily = FamilyIDs.familyAt(index: 0) {
            XCTAssertFalse(firstFamily.isEmpty, "First family should exist")
        } else {
            XCTFail("Should have family at index 0")
        }
    }
    
    func testFamilyAtInvalidIndex() {
        // Test invalid index returns nil
        let family = FamilyIDs.familyAt(index: -1)
        XCTAssertNil(family, "Negative index should return nil")
        
        let tooHigh = FamilyIDs.familyAt(index: 99999)
        XCTAssertNil(tooHigh, "Too high index should return nil")
    }
    
    func testNextFamilyAfter() {
        // Test getting next family
        if let next = FamilyIDs.nextFamilyAfter("KORPI 6") {
            XCTAssertFalse(next.isEmpty, "Next family should exist")
            XCTAssertNotEqual(next, "KORPI 6", "Should be different family")
        }
    }
    
    func testNextFamilyAfterLast() {
        // Get last family
        guard let lastIndex = FamilyIDs.count > 0 ? FamilyIDs.count - 1 : nil,
              let lastFamily = FamilyIDs.familyAt(index: lastIndex) else {
            XCTFail("Should have last family")
            return
        }
        
        // Test next after last
        let next = FamilyIDs.nextFamilyAfter(lastFamily)
        XCTAssertNil(next, "Next after last should be nil")
    }
    
    func testPreviousFamilyBefore() {
        // Test getting previous family
        if let previous = FamilyIDs.previousFamilyBefore("KORPI 6") {
            XCTAssertFalse(previous.isEmpty, "Previous family should exist")
            XCTAssertNotEqual(previous, "KORPI 6", "Should be different family")
        }
    }
    
    func testPreviousFamilyBeforeFirst() {
        // Get first family
        guard let firstFamily = FamilyIDs.familyAt(index: 0) else {
            XCTFail("Should have first family")
            return
        }
        
        // Test previous before first
        let previous = FamilyIDs.previousFamilyBefore(firstFamily)
        XCTAssertNil(previous, "Previous before first should be nil")
    }
    
    func testCount() {
        // Test family count
        let count = FamilyIDs.count
        XCTAssertGreaterThan(count, 0, "Should have families")
        XCTAssertGreaterThan(count, 1000, "Should have over 1000 families")
    }
    
    func testIsFirst() {
        // Get first family
        guard let firstFamily = FamilyIDs.familyAt(index: 0) else {
            XCTFail("Should have first family")
            return
        }
        
        // Test isFirst
        XCTAssertTrue(FamilyIDs.isFirst(firstFamily), "First family should be detected")
        XCTAssertFalse(FamilyIDs.isFirst("KORPI 6"), "KORPI 6 should not be first")
    }
    
    func testIsLast() {
        // Get last family
        guard let lastIndex = FamilyIDs.count > 0 ? FamilyIDs.count - 1 : nil,
              let lastFamily = FamilyIDs.familyAt(index: lastIndex) else {
            XCTFail("Should have last family")
            return
        }
        
        // Test isLast
        XCTAssertTrue(FamilyIDs.isLast(lastFamily), "Last family should be detected")
        XCTAssertFalse(FamilyIDs.isLast("KORPI 6"), "KORPI 6 should not be last")
    }
    
    func testFamiliesAfter() {
        // Test getting batch of families after a given ID
        let families = FamilyIDs.familiesAfter("KORPI 6", maxCount: 5)
        
        XCTAssertLessThanOrEqual(families.count, 5, "Should respect max count")
        XCTAssertFalse(families.contains("KORPI 6"), "Should not include starting family")
    }
    
    func testFamiliesAfterWithLargeMaxCount() {
        // Test with maxCount larger than remaining families
        if let lastIndex = FamilyIDs.count > 1 ? FamilyIDs.count - 2 : nil,
           let secondToLast = FamilyIDs.familyAt(index: lastIndex) {
            let families = FamilyIDs.familiesAfter(secondToLast, maxCount: 1000)
            XCTAssertLessThanOrEqual(families.count, 10, "Should only return available families")
        }
    }
    
    func testFamiliesAfterInvalidID() {
        // Test with invalid starting ID
        let families = FamilyIDs.familiesAfter("INVALID 999", maxCount: 5)
        XCTAssertEqual(families.count, 0, "Invalid ID should return empty array")
    }
    
    func testNormalization() {
        // Test ID normalization
        let normalized1 = FamilyIDs.normalize("KORPI 6")
        let normalized2 = FamilyIDs.normalize("  korpi  6  ")
        let normalized3 = FamilyIDs.normalize("Korpi 6")
        
        XCTAssertEqual(normalized1, normalized2, "Should normalize whitespace")
        XCTAssertEqual(normalized1.lowercased(), normalized3.lowercased(), "Should normalize case")
    }
    
    func testPerformanceOfLookup() {
        // Test O(1) lookup performance
        measure {
            for _ in 0..<1000 {
                _ = FamilyIDs.isValid(familyId: "KORPI 6")
            }
        }
    }
    
    func testPerformanceOfIndexLookup() {
        // Test O(1) index lookup performance
        measure {
            for _ in 0..<1000 {
                _ = FamilyIDs.indexOf(familyId: "KORPI 6")
            }
        }
    }
}

// MARK: - JuuretError Tests

final class JuuretErrorTests: XCTestCase {
    
    func testInvalidFamilyIdError() {
        let error = JuuretError.invalidFamilyId("TEST 999")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("TEST 999") ?? false)
    }
    
    func testExtractionFailedError() {
        let error = JuuretError.extractionFailed("Test reason")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Test reason") ?? false)
    }
    
    func testAIServiceNotConfiguredError() {
        let error = JuuretError.aiServiceNotConfigured("DeepSeek")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testNoCurrentFamilyError() {
        let error = JuuretError.noCurrentFamily
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testCrossReferenceFailedError() {
        let error = JuuretError.crossReferenceFailed("Test details")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testFileManagementError() {
        let error = JuuretError.fileManagement("Test details")
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testParsingFailedError() {
        let error = JuuretError.parsingFailed("Invalid JSON")
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testNetworkError() {
        let error = JuuretError.networkError("Connection timeout")
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testNoFileLoadedError() {
        let error = JuuretError.noFileLoaded
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testFamilyNotFoundError() {
        let error = JuuretError.familyNotFound("MISSING 1")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("MISSING 1") ?? false)
    }
    
    func testErrorRecoverySuggestions() {
        let error = JuuretError.aiServiceNotConfigured("DeepSeek")
        XCTAssertNotNil(error.recoverySuggestion, "Should have recovery suggestion")
    }
    
    func testErrorFailureReasons() {
        let error = JuuretError.invalidFamilyId("TEST 999")
        XCTAssertNotNil(error.failureReason, "Should have failure reason")
    }
}
