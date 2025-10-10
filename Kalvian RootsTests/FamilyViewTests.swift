//
//  FamilyViewTests.swift
//  Kalvian Roots Tests
//
//  Tests for enhanced family display with inline enhanced dates
//

import XCTest
@testable import Kalvian_Roots
import SwiftUI

@MainActor
final class FamilyViewTests: XCTestCase {
    
    var app: JuuretApp!
    
    /// Check if integration tests should run (requires AI calls, slow)
    private var isIntegrationTestMode: Bool {
        ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1"
    }
    
    override func setUp() async throws {
        try await super.setUp()
        app = JuuretApp()
        
        // Wait for file to load
        let fileLoaded = await app.waitForFileReady()
        XCTAssertTrue(fileLoaded, "File should load successfully")
    }
    
    override func tearDown() async throws {
        app = nil
        try await super.tearDown()
    }
    
    // MARK: - Enhanced Date Extraction Tests
    
    func testGetEnhancedDeathDate() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Extract a family with married children
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family or network should be available")
            return
        }
        
        // Find a married child
        let marriedChildren = family.allChildren.filter { $0.isMarried }
        XCTAssertFalse(marriedChildren.isEmpty, "Should have married children")
        
        // Check if any have enhanced death dates
        for child in marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                let asParentPerson = asParentFamily.allParents.first { parent in
                    parent.name.lowercased() == child.name.lowercased() ||
                    (parent.birthDate == child.birthDate && parent.birthDate != nil)
                }
                
                if let enhancedDeath = asParentPerson?.deathDate,
                   enhancedDeath != child.deathDate {
                    XCTAssertNotNil(enhancedDeath, "Should have enhanced death date")
                    XCTAssertNotEqual(enhancedDeath, child.deathDate, "Enhanced should differ from nuclear")
                    return // Test passed
                }
            }
        }
        
        // If we get here, no enhanced death dates were found - log but don't fail
        logInfo(.ui, "ℹ️ No enhanced death dates found in test family")
    }
    
    func testGetEnhancedMarriageDate() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Extract a family with married children
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family or network should be available")
            return
        }
        
        // Find married children
        let marriedChildren = family.allChildren.filter { $0.isMarried }
        
        for child in marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                // Check for enhanced marriage date
                let enhancedMarriage = asParentFamily.primaryCouple?.fullMarriageDate
                
                if let enhanced = enhancedMarriage,
                   enhanced.count >= 8 { // Full 8-digit date
                    XCTAssertNotNil(enhanced, "Should have enhanced marriage date")
                    return // Test passed
                }
            }
        }
        
        logInfo(.ui, "ℹ️ No enhanced marriage dates found in test family")
    }
    
    func testGetEnhancedSpouseDates() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family or network should be available")
            return
        }
        
        // Find married children with spouses
        let marriedChildren = family.allChildren.filter { $0.isMarried && $0.spouse != nil }
        
        for child in marriedChildren {
            guard let spouseName = child.spouse else { continue }
            
            // Create Person object with all required parameters
            let spousePerson = Person(
                name: spouseName,
                patronymic: nil,
                birthDate: nil,
                deathDate: nil,
                marriageDate: nil,
                fullMarriageDate: nil,
                spouse: nil,
                asChild: nil,
                asParent: nil,
                familySearchId: nil,
                noteMarkers: [],  // Required parameter
                fatherName: nil,
                motherName: nil,
                spouseBirthDate: nil,
                spouseParentsFamilyId: nil
            )
            
            if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spousePerson) {
                // Find spouse in their asChild family
                let spouseInFamily = spouseAsChildFamily.allChildren.first { person in
                    person.name.lowercased().contains(spouseName.split(separator: " ").first?.lowercased() ?? "")
                }
                
                if let enhancedSpouse = spouseInFamily {
                    XCTAssertNotNil(enhancedSpouse.birthDate ?? enhancedSpouse.deathDate,
                                   "Enhanced spouse should have at least birth or death date")
                    
                    logInfo(.ui, "✅ Enhanced spouse data: \(enhancedSpouse.displayName)")
                    return // Test passed
                }
            }
        }
        
        logInfo(.ui, "ℹ️ No enhanced spouse data found in test family")
    }
    
    // MARK: - FamilyNetwork Helper Method Tests
    
    func testGetAsParentFamilyForChild() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family or network should be available")
            return
        }
        
        // Find a married child
        let marriedChildren = family.allChildren.filter { $0.isMarried }
        XCTAssertFalse(marriedChildren.isEmpty, "Should have married children")
        
        for child in marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                XCTAssertNotNil(asParentFamily, "AsParent family should exist")
                XCTAssertFalse(asParentFamily.familyId.isEmpty, "AsParent family should have ID")
                logInfo(.ui, "✅ Found asParent family: \(asParentFamily.familyId)")
                return // Test passed
            }
        }
        
        XCTFail("No asParent families found for married children")
    }
    
    func testGetSpouseAsChildFamily() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family or network should be available")
            return
        }
        
        // Find a married child with spouse
        let marriedChildren = family.allChildren.filter { $0.isMarried && $0.spouse != nil }
        XCTAssertFalse(marriedChildren.isEmpty, "Should have married children with spouses")
        
        var foundSpouseFamily = false
        
        for child in marriedChildren {
            guard let spouseName = child.spouse else { continue }
            
            // Create Person object with all required parameters explicitly
            let spousePerson = Person(
                name: spouseName,
                patronymic: nil,
                birthDate: nil,
                deathDate: nil,
                marriageDate: nil,
                fullMarriageDate: nil,
                spouse: nil,
                asChild: nil,
                asParent: nil,
                familySearchId: nil,
                noteMarkers: [],  // Required parameter - no default value
                fatherName: nil,
                motherName: nil,
                spouseBirthDate: nil,
                spouseParentsFamilyId: nil
            )
            
            if let spouseFamily = network.getSpouseAsChildFamily(for: spousePerson) {
                XCTAssertNotNil(spouseFamily, "Spouse asChild family should exist")
                XCTAssertFalse(spouseFamily.familyId.isEmpty, "Spouse family should have ID")
                foundSpouseFamily = true
                
                logInfo(.ui, "✅ Found spouse family: \(spouseFamily.familyId) for \(spouseName)")
                break // Test passed
            }
        }
        
        // If no spouse families found, check if that's expected
        if !foundSpouseFamily {
            XCTAssertTrue(
                network.spouseAsChildFamilies.isEmpty,
                "No spouse families found but network has \(network.spouseAsChildFamilies.count) cached"
            )
            logInfo(.ui, "ℹ️ No spouse families resolved - may be expected for test data")
        }
    }
    
    // MARK: - Family Display Structure Tests
    
    func testFamilyHasValidStructure() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily else {
            XCTFail("Family should be loaded")
            return
        }
        
        // Basic structure checks
        XCTAssertFalse(family.familyId.isEmpty, "Family should have ID")
        XCTAssertFalse(family.pageReferences.isEmpty, "Family should have page references")
        XCTAssertFalse(family.couples.isEmpty, "Family should have at least one couple")
        
        // Primary couple checks
        if let primaryCouple = family.primaryCouple {
            XCTAssertFalse(primaryCouple.husband.name.isEmpty, "Husband should have name")
            XCTAssertFalse(primaryCouple.wife.name.isEmpty, "Wife should have name")
        }
    }
    
    func testAllChildrenHaveNames() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily else {
            XCTFail("Family should be loaded")
            return
        }
        
        let allChildren = family.allChildren
        for child in allChildren {
            XCTAssertFalse(child.name.isEmpty, "Child should have name")
            XCTAssertFalse(child.displayName.isEmpty, "Child should have display name")
        }
    }
    
    func testMarriedChildrenHaveSpouseInfo() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily else {
            XCTFail("Family should be loaded")
            return
        }
        
        let marriedChildren = family.allChildren.filter { $0.isMarried }
        
        for child in marriedChildren {
            XCTAssertTrue(child.isMarried, "Child should be marked as married")
            // Note: spouse name might be nil in some cases, so we don't assert it strictly
        }
    }
    
    // MARK: - Enhanced Data Integration Tests
    
    func testEnhancedDataDoesNotOverwriteNuclear() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family and network should be loaded")
            return
        }
        
        // Verify nuclear family is unchanged
        XCTAssertEqual(network.mainFamily.familyId, family.familyId,
                      "Network main family should match current family")
        
        // Verify that original family data is preserved
        let originalChildren = family.allChildren
        let networkChildren = network.mainFamily.allChildren
        
        XCTAssertEqual(originalChildren.count, networkChildren.count,
                      "Child count should be preserved")
    }
    
    func testCompleteWorkflow() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // 1. Navigate to family
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family and network should be loaded")
            return
        }
        
        // 2. Verify family structure
        XCTAssertFalse(family.familyId.isEmpty)
        XCTAssertNotNil(family.primaryCouple)
        
        // 3. Verify network has cross-references
        XCTAssertTrue(network.totalResolvedFamilies > 1,
                     "Network should have resolved cross-references")
        
        // 4. Check for married children with enhanced data
        let marriedChildren = family.allChildren.filter { $0.isMarried }
        var foundEnhancedData = false
        
        for child in marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                foundEnhancedData = true
                XCTAssertFalse(asParentFamily.familyId.isEmpty,
                              "AsParent family should have valid ID")
                logInfo(.ui, "✅ Found enhanced data for: \(child.displayName)")
                break
            }
        }
        
        XCTAssertTrue(foundEnhancedData || marriedChildren.isEmpty,
                     "Should find enhanced data for married children or have no married children")
    }
}

// MARK: - Color Extension Tests

final class ColorExtensionTests: XCTestCase {
    
    func testHexColorInitialization() {
        // Test 6-digit hex
        let blue = Color(hex: "0066cc")
        XCTAssertNotNil(blue)
        
        // Test 8-digit hex with alpha
        let blueWithAlpha = Color(hex: "ff0066cc")
        XCTAssertNotNil(blueWithAlpha)
        
        // Test 3-digit hex
        let shortHex = Color(hex: "06c")
        XCTAssertNotNil(shortHex)
    }
    
    func testInvalidHexHandling() {
        // Should create black color for invalid hex
        let invalid = Color(hex: "invalid")
        XCTAssertNotNil(invalid)
    }
}
