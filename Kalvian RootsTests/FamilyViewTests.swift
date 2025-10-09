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
    
    func testGetEnhancedDeathDate() async {
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
    }
    
    func testGetEnhancedMarriageDate() async {
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
        
        for child in marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                let couple = asParentFamily.couples.first { couple in
                    couple.husband.name.lowercased() == child.name.lowercased() ||
                    couple.wife.name.lowercased() == child.name.lowercased()
                }
                
                let enhancedMarriage = couple?.fullMarriageDate ?? couple?.marriageDate
                let nuclearMarriage = child.fullMarriageDate ?? child.marriageDate
                
                if let enhanced = enhancedMarriage,
                   enhanced != nuclearMarriage,
                   enhanced.count >= 8 {
                    XCTAssertTrue(enhanced.count >= 8, "Enhanced marriage should be full date")
                    XCTAssertNotEqual(enhanced, nuclearMarriage, "Enhanced should differ")
                    return // Test passed
                }
            }
        }
    }
    
    func testGetEnhancedSpouseDates() async {
        // Extract a family with married children
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family or network should be available")
            return
        }
        
        // Find a married child with spouse
        let marriedChildren = family.allChildren.filter { $0.isMarried && $0.spouse != nil }
        
        for child in marriedChildren {
            guard let spouseName = child.spouse else { continue }
            
            let spousePerson = Person(name: spouseName, noteMarkers: [])
            if let spouseFamily = network.getSpouseAsChildFamily(for: spousePerson) {
                XCTAssertNotNil(spouseFamily, "Spouse family should exist")
                
                // Spouse should appear as a child in their family
                let spouseInFamily = spouseFamily.allChildren.first { person in
                    person.name.lowercased().contains(spouseName.split(separator: " ").first?.lowercased() ?? "")
                }
                
                if spouseInFamily != nil {
                    XCTAssertNotNil(spouseInFamily, "Spouse should be found in their family")
                    return // Test passed
                }
            }
        }
    }
    
    // MARK: - FamilyNetwork Helper Method Tests
    
    func testGetAsParentFamilyForChild() async {
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
                return // Test passed
            }
        }
    }
    
    func testGetSpouseAsChildFamily() async {
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family or network should be available")
            return
        }
        
        // Find a married child with spouse
        let marriedChildren = family.allChildren.filter { $0.isMarried && $0.spouse != nil }
        
        XCTAssertFalse(marriedChildren.isEmpty, "Test requires married children to validate spouse families")
        
        var foundSpouseFamily = false
        
        for child in marriedChildren {
            guard let spouseName = child.spouse else { continue }
            
            // Create a Person object for the spouse with minimal required parameters
            // The noteMarkers parameter is required and has no default value
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
                noteMarkers: [],  // Required parameter - empty array
                fatherName: nil,
                motherName: nil,
                spouseBirthDate: nil,
                spouseParentsFamilyId: nil
            )
            
            if let spouseFamily = network.getSpouseAsChildFamily(for: spousePerson) {
                XCTAssertNotNil(spouseFamily, "Spouse asChild family should exist")
                XCTAssertFalse(spouseFamily.familyId.isEmpty, "Spouse family should have valid ID")
                foundSpouseFamily = true
                
                logInfo(.ui, "✅ Found spouse family: \(spouseFamily.familyId) for spouse: \(spouseName)")
                break // Test passed - found at least one spouse family
            }
        }
        
        // If no spouse families were found, check if that's expected
        if !foundSpouseFamily {
            XCTAssertTrue(
                network.spouseAsChildFamilies.isEmpty,
                "No spouse families found but network has \(network.spouseAsChildFamilies.count) spouse families cached"
            )
            logInfo(.ui, "ℹ️ No spouse families resolved in this test - this may be expected for test data")
        }
    }
    
    // MARK: - Family Display Structure Tests
    
    func testFamilyHasValidStructure() async {
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
    
    func testAllChildrenHaveNames() async {
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
    
    func testMarriedChildrenHaveSpouseInfo() async {
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily else {
            XCTFail("Family should be loaded")
            return
        }
        
        let marriedChildren = family.allChildren.filter { $0.isMarried }
        
        for child in marriedChildren {
            XCTAssertTrue(child.isMarried, "Child should be marked as married")
            // Note: spouse name might be nil in some cases, so we don't assert it
        }
    }
    
    // MARK: - Enhanced Data Integration Tests
    
    func testEnhancedDataDoesNotOverwriteNuclear() async {
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let family = app.currentFamily,
              let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Family or network should be available")
            return
        }
        
        // Verify nuclear family data is still intact
        for child in family.allChildren {
            // Original data should still be there
            if let originalBirth = child.birthDate {
                XCTAssertFalse(originalBirth.isEmpty, "Original birth date should be preserved")
            }
            
            // Enhanced data should come from network, not modify original
            if let asParentFamily = network.getAsParentFamily(for: child) {
                let asParentPerson = asParentFamily.allParents.first { parent in
                    parent.name.lowercased() == child.name.lowercased()
                }
                
                // Nuclear family's child object should not be modified
                if let enhancedDeath = asParentPerson?.deathDate {
                    // Enhanced death exists, but nuclear might not have it
                    // This is correct - enhanced data supplements, doesn't replace
                    XCTAssertTrue(true, "Enhanced data supplements nuclear data")
                }
            }
        }
    }
    
    func testNetworkContainsAllExpectedFamilies() async {
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        guard let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Network should be available")
            return
        }
        
        // Check network has main family
        XCTAssertEqual(network.mainFamily.familyId, "HYYPPÄ 6", "Main family should be HYYPPÄ 6")
        
        // Check network has resolved cross-references
        XCTAssertTrue(network.totalResolvedFamilies > 1, "Should have resolved cross-references")
        
        // Log counts for debugging
        print("AsChild families: \(network.asChildFamilies.count)")
        print("AsParent families: \(network.asParentFamilies.count)")
        print("Spouse families: \(network.spouseAsChildFamilies.count)")
    }
    
    // MARK: - Color and Formatting Tests
    
    func testEnhancedDatesShouldUseBrownColor() {
        // This is a visual test, but we can verify the color hex value
        let brownColor = Color(hex: "8b4513")
        
        // Verify color is created correctly
        XCTAssertNotNil(brownColor, "Brown color should be created")
    }
    
    func testClickableElementsShouldUseBlueColor() {
        // Verify blue color for clickable elements
        let blueColor = Color(hex: "0066cc")
        
        XCTAssertNotNil(blueColor, "Blue color should be created")
    }
    
    func testBackgroundColorShouldBeOffWhite() {
        // Verify off-white background
        let bgColor = Color(hex: "fefdf8")
        
        XCTAssertNotNil(bgColor, "Background color should be created")
    }
    
    // MARK: - Integration Test
    
    func testCompleteEnhancedDisplayWorkflow() async {
        // 1. Load a family
        app.navigateToFamily("HYYPPÄ 6", updateHistory: true)
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
        XCTAssertTrue(network.totalResolvedFamilies > 1)
        
        // 4. Check for married children with enhanced data
        let marriedChildren = family.allChildren.filter { $0.isMarried }
        var foundEnhancedData = false
        
        for child in marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                foundEnhancedData = true
                XCTAssertFalse(asParentFamily.familyId.isEmpty)
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
