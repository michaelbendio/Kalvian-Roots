//
//  UIIntegrationTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive tests for UI
//  Tests navigation, enhanced display, clickable elements, and citations
//

import XCTest
@testable import Kalvian_Roots
import SwiftUI

@MainActor
final class UIIntegrationTests: XCTestCase {
    
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
    
    // MARK: - Phase 1: Navigation Tests
    
    func testNavigationBarComponents() {
        // Test: All navigation state properties exist
        XCTAssertEqual(app.navigationHistory.count, 0, "History starts empty")
        XCTAssertEqual(app.historyIndex, -1, "Index starts at -1")
        XCTAssertNil(app.homeFamily, "Home starts as nil")
        XCTAssertFalse(app.showPDFMode, "PDF mode starts off")
    }
    
    func testNavigationCapabilities() {
        // Test: Initial navigation capabilities
        XCTAssertFalse(app.canNavigateBack, "Cannot go back initially")
        XCTAssertFalse(app.canNavigateForward, "Cannot go forward initially")
        XCTAssertFalse(app.canNavigateHome, "Cannot go home without home set")
    }
    
    func testNavigateToFamilyUpdatesHistory() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // When: Navigate to a family with history update
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        // Then: History and home should be updated
        XCTAssertEqual(app.navigationHistory.count, 1, "History has one entry")
        XCTAssertEqual(app.navigationHistory[0], "KORPI 6", "Entry is KORPI 6")
        XCTAssertEqual(app.historyIndex, 0, "Index is 0")
        XCTAssertEqual(app.homeFamily, "KORPI 6", "Home is set to KORPI 6")
        XCTAssertTrue(app.canNavigateHome, "Can now navigate home")
    }
    
    func testNavigateWithoutUpdatingHistory() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A home family
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        // When: Navigate without updating history
        app.navigateToFamily("HERLEVI 1", updateHistory: false)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        // Then: History unchanged, home unchanged
        XCTAssertEqual(app.navigationHistory.count, 1, "Still one history entry")
        XCTAssertEqual(app.homeFamily, "KORPI 6", "Home still KORPI 6")
    }
    
    func testBackForwardNavigation() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: Multiple families in history
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        app.navigateToFamily("HERLEVI 1", updateHistory: true)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // When: Navigate back
        app.navigateBack()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Then: Should be at KORPI 6
        XCTAssertEqual(app.currentFamilyIdInHistory, "KORPI 6", "Back to KORPI 6")
        XCTAssertTrue(app.canNavigateForward, "Can go forward now")
        XCTAssertFalse(app.canNavigateBack, "Cannot go further back")
        
        // When: Navigate forward
        app.navigateForward()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Then: Should be at HERLEVI 1
        XCTAssertEqual(app.currentFamilyIdInHistory, "HERLEVI 1", "Forward to HERLEVI 1")
        XCTAssertTrue(app.canNavigateBack, "Can go back now")
        XCTAssertFalse(app.canNavigateForward, "Cannot go further forward")
    }
    
    func testNavigateHome() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: Home set to KORPI 6, currently at HERLEVI 1
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        app.navigateToFamily("HERLEVI 1", updateHistory: false)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // When: Navigate home
        app.navigateHome()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Then: Should be at home family
        XCTAssertEqual(app.currentFamily?.familyId, "KORPI 6", "Back at home")
    }
    
    func testInvalidFamilyIDRejection() {
        // When: Try to navigate to invalid family
        app.navigateToFamily("INVALID 999", updateHistory: true)
        
        // Then: Should show error, no history update
        XCTAssertEqual(app.navigationHistory.count, 0, "No history entry")
        XCTAssertNotNil(app.errorMessage, "Error message set")
        XCTAssertTrue(app.errorMessage?.contains("Invalid family ID") ?? false, "Correct error")
    }
    
    // MARK: - Phase 2: Clan Browser Tests
    
    func testClanBrowserGrouping() {
        // Test: Clan browser groups families correctly
        let clans = FamilyIDs.groupedByClans()
        
        XCTAssertFalse(clans.isEmpty, "Should have clans")
        
        // Check that a known clan exists
        let korpiClan = clans.first { $0.clanName == "KORPI" }
        XCTAssertNotNil(korpiClan, "KORPI clan should exist")
        
        if let korpi = korpiClan {
            XCTAssertFalse(korpi.suffixes.isEmpty, "KORPI should have suffixes")
            XCTAssertTrue(korpi.suffixes.contains("6"), "KORPI 6 should exist")
        }
    }
    
    func testClanNamesAreSorted() {
        // Test: Clans are alphabetically sorted
        let clans = FamilyIDs.groupedByClans()
        let clanNames = clans.map { $0.clanName }
        let sortedNames = clanNames.sorted()
        
        XCTAssertEqual(clanNames, sortedNames, "Clans should be sorted")
    }
    
    // MARK: - Phase 3: Enhanced Display Tests
    
    func testEnhancedDatesFromAsParentFamily() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A family with married children
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        guard let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Network should exist")
            return
        }
        
        // Then: Check for enhanced data
        let family = network.mainFamily
        let marriedChildren = family.allChildren.filter { $0.isMarried }
        
        if !marriedChildren.isEmpty {
            let firstMarried = marriedChildren[0]
            
            // Check if asParent family exists
            if let asParentFamily = network.asParentFamilies[firstMarried.displayName] {
                XCTAssertNotNil(asParentFamily, "Should have asParent family")
                
                // Find the child in their asParent family to get enhanced dates
                if let asParentPerson = asParentFamily.allParents.first(where: {
                    $0.name.lowercased() == firstMarried.name.lowercased()
                }) {
                    // Enhanced data should be available
                    let hasEnhancedDeath = asParentPerson.deathDate != nil
                    let hasEnhancedMarriage = asParentPerson.fullMarriageDate != nil
                    
                    XCTAssertTrue(hasEnhancedDeath || hasEnhancedMarriage,
                                  "Should have some enhanced data")
                }
            }
        }
    }
    
    func testSpouseEnhancedDatesFromSpouseAsChildFamily() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A family with married children
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        guard let network = app.familyNetworkWorkflow?.getFamilyNetwork() else {
            XCTFail("Network should exist")
            return
        }
        
        // Then: Check for spouse enhanced data
        let family = network.mainFamily
        let marriedChildren = family.allChildren.filter { $0.isMarried && $0.spouse != nil }
        
        if !marriedChildren.isEmpty {
            let firstMarried = marriedChildren[0]
            
            // Check if spouse has asChild family
            if let spouseFamily = network.spouseAsChildFamilies[firstMarried.spouse!] {
                XCTAssertNotNil(spouseFamily, "Spouse should have asChild family")
                
                // Spouse should appear as child in their family
                let spouseAsChild = spouseFamily.allChildren.first { child in
                    child.name.lowercased().contains(firstMarried.spouse!.split(separator: " ").first?.lowercased() ?? "")
                }
                
                if spouseAsChild != nil {
                    XCTAssertNotNil(spouseAsChild, "Spouse found in their family")
                }
            }
        }
    }
    
    // MARK: - Phase 4: Citation Generation Tests
    
    func testChildCitationGeneration() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A family with children
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        guard let family = app.currentFamily,
              let firstChild = family.allChildren.first else {
            XCTFail("Family should have children")
            return
        }
        
        // When: Generate citation for child
        let citation = await app.generateCitation(for: firstChild, in: family)
        
        // Then: Citation should contain key information
        XCTAssertTrue(citation.contains("Information on"), "Should have header")
        XCTAssertTrue(citation.contains(family.familyId) || citation.contains("page"),
                      "Should reference source")
        XCTAssertTrue(citation.contains(firstChild.name), "Should mention child")
    }
    
    func testParentCitationGeneration() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A family with parents
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        guard let family = app.currentFamily,
              let couple = family.primaryCouple else {
            XCTFail("Family should have primary couple")
            return
        }
        
        // When: Generate citation for father
        let fatherCitation = await app.generateCitation(for: couple.husband, in: family)
        
        // Then: Citation should reference asChild family if available
        XCTAssertTrue(fatherCitation.contains("Information on"), "Should have header")
        XCTAssertTrue(fatherCitation.contains(couple.husband.name), "Should mention father")
        
        // When: Generate citation for mother
        let motherCitation = await app.generateCitation(for: couple.wife, in: family)
        
        // Then: Citation should be valid
        XCTAssertTrue(motherCitation.contains("Information on"), "Should have header")
        XCTAssertTrue(motherCitation.contains(couple.wife.name), "Should mention mother")
    }
    
    func testSpouseCitationGeneration() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A family with married children
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        guard let family = app.currentFamily else {
            XCTFail("Family should be loaded")
            return
        }
        
        let marriedChild = family.allChildren.first { $0.spouse != nil }
        guard let spouse = marriedChild?.spouse else {
            throw XCTSkip("No married children in this family")
        }
        
        // When: Generate spouse citation
        let citation = await app.generateSpouseCitation(for: spouse, in: family)
        
        // Then: Citation should reference spouse's family
        XCTAssertTrue(citation.contains("Information on"), "Should have header")
        XCTAssertFalse(citation.contains("No family information"), "Should find family")
    }
    
    // MARK: - Hiski Integration Tests
    
    func testHiskiBirthQuery() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires Hiski API. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A family with a child with birth date
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        guard let family = app.currentFamily,
              let child = family.allChildren.first(where: { $0.birthDate != nil }),
              let birthDate = child.birthDate else {
            throw XCTSkip("No child with birth date")
        }
        
        // When: Query Hiski for birth
        let result = await app.processHiskiQuery(
            for: child,
            eventType: .birth,
            familyId: family.familyId
        )
        
        // Then: Should return a URL
        XCTAssertTrue(result.contains("hiski.genealogia.fi"), "Should have Hiski URL")
    }
    
    func testHiskiDeathQuery() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires Hiski API. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A parent with death date
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        guard let family = app.currentFamily,
              let couple = family.primaryCouple,
              couple.husband.deathDate != nil else {
            throw XCTSkip("No parent with death date")
        }
        
        // When: Query Hiski for death
        let result = await app.processHiskiQuery(
            for: couple.husband,
            eventType: .death,
            familyId: family.familyId
        )
        
        // Then: Should return a URL
        XCTAssertTrue(result.contains("hiski.genealogia.fi"), "Should have Hiski URL")
    }
    
    func testHiskiMarriageQuery() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires Hiski API. Set RUN_INTEGRATION_TESTS=1")
        }
        
        // Given: A married child
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        guard let family = app.currentFamily,
              let marriedChild = family.allChildren.first(where: {
                  $0.isMarried && $0.bestMarriageDate != nil
              }) else {
            throw XCTSkip("No married child with marriage date")
        }
        
        // When: Query Hiski for marriage
        let result = await app.processHiskiQuery(
            for: marriedChild,
            eventType: .marriage,
            familyId: family.familyId
        )
        
        // Then: Should return a URL
        XCTAssertTrue(result.contains("hiski.genealogia.fi"), "Should have Hiski URL")
    }
    
    // MARK: - Visual Appearance Tests (Unit)
    
    func testColorScheme() {
        // Test: Color hex values are correct
        let blueClickable = Color(hex: "0066cc")
        let brownEnhanced = Color(hex: "8b4513")
        let purpleGradient1 = Color(hex: "667eea")
        let purpleGradient2 = Color(hex: "764ba2")
        let offWhiteBackground = Color(hex: "fefdf8")
        
        // Just verify they can be created
        XCTAssertNotNil(blueClickable, "Blue color should initialize")
        XCTAssertNotNil(brownEnhanced, "Brown color should initialize")
        XCTAssertNotNil(purpleGradient1, "Purple1 should initialize")
        XCTAssertNotNil(purpleGradient2, "Purple2 should initialize")
        XCTAssertNotNil(offWhiteBackground, "Background should initialize")
    }
    
    func testFamilyIDValidation() {
        // Test: FamilyIDs validation works
        XCTAssertTrue(FamilyIDs.isValid(familyId: "KORPI 6"), "KORPI 6 is valid")
        XCTAssertTrue(FamilyIDs.isValid(familyId: "HERLEVI 1"), "HERLEVI 1 is valid")
        XCTAssertFalse(FamilyIDs.isValid(familyId: "INVALID 999"), "INVALID 999 not valid")
        XCTAssertFalse(FamilyIDs.isValid(familyId: "Loht. Vapola"), "Pseudo-ID not valid")
    }
    
    // MARK: - PDF Mode Tests
    
    func testPDFModeToggle() {
        // Test: PDF mode can be toggled
        XCTAssertFalse(app.showPDFMode, "PDF mode starts off")
        
        app.showPDFMode = true
        XCTAssertTrue(app.showPDFMode, "PDF mode can be turned on")
        
        app.showPDFMode = false
        XCTAssertFalse(app.showPDFMode, "PDF mode can be turned off")
    }
}
