//
//  JuuretAppNavigationTests.swift
//  Kalvian Roots Tests
//
//  Tests for navigation functionality in JuuretApp
//
//  Contains both fast unit tests and slow integration tests.
//  Integration tests require AI calls and are skipped by default.
//  To run integration tests, set environment variable: RUN_INTEGRATION_TESTS=1
//

import XCTest
@testable import Kalvian_Roots

@MainActor
final class JuuretAppNavigationTests: XCTestCase {
    
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
    
    // MARK: - Initial State Tests (Fast - Always Run)
    
    /// Fast unit test - No AI calls required
    func testInitialNavigationState() {
        XCTAssertEqual(app.navigationHistory.count, 0, "History should be empty initially")
        XCTAssertEqual(app.historyIndex, -1, "History index should be -1 initially")
        XCTAssertNil(app.homeFamily, "Home family should be nil initially")
        XCTAssertFalse(app.showPDFMode, "PDF mode should be off initially")
    }
    
    /// Fast unit test - No AI calls required
    func testInitialNavigationCapabilities() {
        XCTAssertFalse(app.canNavigateBack, "Cannot navigate back with empty history")
        XCTAssertFalse(app.canNavigateForward, "Cannot navigate forward with empty history")
        XCTAssertFalse(app.canNavigateHome, "Cannot navigate home with no home set")
        XCTAssertNil(app.currentFamilyIdInHistory, "No current family in empty history")
    }
    
    // MARK: - Navigate To Family Tests (Integration - Require AI)
    
    /// Integration test - Tests navigation with real family extraction
    /// - Requires: RUN_INTEGRATION_TESTS=1
    func testNavigateToFamilyWithHistoryUpdate() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI calls. Set RUN_INTEGRATION_TESTS=1 to run.")
        }
        
        // Navigate to KORPI 6 with history update
        app.navigateToFamily("KORPI 6", updateHistory: true)
        
        // Wait for extraction to complete
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        XCTAssertEqual(app.navigationHistory.count, 1, "History should have 1 entry")
        XCTAssertEqual(app.navigationHistory[0], "KORPI 6", "History should contain KORPI 6")
        XCTAssertEqual(app.historyIndex, 0, "Index should be 0")
        XCTAssertEqual(app.homeFamily, "KORPI 6", "Home should be set to KORPI 6")
        XCTAssertEqual(app.currentFamilyIdInHistory, "KORPI 6", "Current family should be KORPI 6")
    }
    
    /// Integration test - Tests navigation without history update
    /// - Requires: RUN_INTEGRATION_TESTS=1
    func testNavigateToFamilyWithoutHistoryUpdate() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI calls. Set RUN_INTEGRATION_TESTS=1 to run.")
        }
        
        // First navigate with history to establish a home
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        // Navigate to HERLEVI 1 without history update
        app.navigateToFamily("HERLEVI 1", updateHistory: false)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        XCTAssertEqual(app.navigationHistory.count, 1, "History should still have 1 entry")
        XCTAssertEqual(app.navigationHistory[0], "KORPI 6", "History should still be KORPI 6")
        XCTAssertEqual(app.homeFamily, "KORPI 6", "Home should still be KORPI 6")
    }
    
    /// Fast unit test - No AI calls required
    func testNavigateToInvalidFamily() {
        app.navigateToFamily("INVALID 999", updateHistory: true)
        
        XCTAssertEqual(app.navigationHistory.count, 0, "Invalid ID should not be added to history")
        XCTAssertNotNil(app.errorMessage, "Error message should be set")
        XCTAssertTrue(app.errorMessage?.contains("Invalid family ID") ?? false, "Error should mention invalid ID")
    }
    
    /// Integration test - Tests case-insensitive navigation
    /// - Requires: RUN_INTEGRATION_TESTS=1
    func testNavigateToCaseInsensitiveFamily() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI calls. Set RUN_INTEGRATION_TESTS=1 to run.")
        }
        
        // Test lowercase
        app.navigateToFamily("korpi 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        XCTAssertEqual(app.navigationHistory[0], "KORPI 6", "Should normalize to uppercase")
        XCTAssertEqual(app.homeFamily, "KORPI 6", "Home should be uppercase")
    }
    
    /// Integration test - Tests whitespace handling in family IDs
    /// - Requires: RUN_INTEGRATION_TESTS=1
    func testNavigateToFamilyWithWhitespace() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - requires AI calls. Set RUN_INTEGRATION_TESTS=1 to run.")
        }
        
        app.navigateToFamily("  KORPI 6  ", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        XCTAssertEqual(app.navigationHistory[0], "KORPI 6", "Should trim whitespace")
    }
    
    // MARK: - History Management Tests (Fast with Integration options)
    
    /// Fast unit test - Tests history state without extraction
    func testHistoryStateManagement() {
        // Manually set history to test state management
        app.navigationHistory = ["KORPI 6", "HERLEVI 1", "SIKALA 3"]
        app.historyIndex = 2
        
        XCTAssertEqual(app.navigationHistory.count, 3, "History should have 3 entries")
        XCTAssertEqual(app.historyIndex, 2, "Index should be 2")
        XCTAssertEqual(app.currentFamilyIdInHistory, "SIKALA 3", "Current should be SIKALA 3")
        
        XCTAssertTrue(app.canNavigateBack, "Should be able to go back")
        XCTAssertFalse(app.canNavigateForward, "Should not be able to go forward")
    }
    
    /// Integration test - Tests multiple navigations with real extraction
    /// - Requires: RUN_INTEGRATION_TESTS=1
    func testMultipleNavigationsBuildsHistory() async throws {
        guard isIntegrationTestMode else {
            throw XCTSkip("Integration test - multiple AI calls. Set RUN_INTEGRATION_TESTS=1 to run.")
        }
        
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        app.navigateToFamily("HERLEVI 1", updateHistory: true)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        app.navigateToFamily("SIKALA 3", updateHistory: true)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        XCTAssertEqual(app.navigationHistory.count, 3, "History should have 3 entries")
        XCTAssertEqual(app.historyIndex, 2, "Index should be 2")
        XCTAssertEqual(app.homeFamily, "SIKALA 3", "Home should be the last family")
    }
    
    func testNavigatingBackThenForwardClearsForwardHistory() async {
        // Build history
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        app.navigateToFamily("HERLEVI 1", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        app.navigateToFamily("SIKALA 3", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Go back once
        app.navigateBack()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.historyIndex, 1, "Should be at index 1")
        
        // Navigate to new family - should clear forward history
        app.navigateToFamily("RAHKONEN 5", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.navigationHistory.count, 3, "History should have 3 entries")
        XCTAssertEqual(app.navigationHistory[2], "RAHKONEN 5", "New family should replace forward history")
        XCTAssertEqual(app.historyIndex, 2, "Index should be 2")
    }
    
    // MARK: - Navigate Back Tests
    
    func testNavigateBack() async {
        // Build history
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        app.navigateToFamily("HERLEVI 1", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Navigate back
        app.navigateBack()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.historyIndex, 0, "Index should be 0")
        XCTAssertEqual(app.currentFamilyIdInHistory, "KORPI 6", "Should be back at KORPI 6")
        XCTAssertTrue(app.canNavigateForward, "Should be able to go forward")
        XCTAssertFalse(app.canNavigateBack, "Should not be able to go back further")
    }
    
    func testNavigateBackAtStart() {
        // Try to navigate back with empty history
        app.navigateBack()
        
        XCTAssertEqual(app.historyIndex, -1, "Index should still be -1")
    }
    
    // MARK: - Navigate Forward Tests
    
    func testNavigateForward() async {
        // Build history and go back
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        app.navigateToFamily("HERLEVI 1", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        app.navigateBack()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Navigate forward
        app.navigateForward()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.historyIndex, 1, "Index should be 1")
        XCTAssertEqual(app.currentFamilyIdInHistory, "HERLEVI 1", "Should be forward at HERLEVI 1")
        XCTAssertFalse(app.canNavigateForward, "Should not be able to go forward further")
        XCTAssertTrue(app.canNavigateBack, "Should be able to go back")
    }
    
    func testNavigateForwardAtEnd() async {
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Try to navigate forward when at end
        app.navigateForward()
        
        XCTAssertEqual(app.historyIndex, 0, "Index should still be 0")
    }
    
    // MARK: - Navigate Home Tests
    
    func testNavigateHome() async {
        // Set home
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Navigate elsewhere without history
        app.navigateToFamily("HERLEVI 1", updateHistory: false)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Navigate home
        app.navigateHome()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.currentFamily?.familyId, "KORPI 6", "Should be back at home")
    }
    
    func testNavigateHomeWithNoHomeSet() {
        app.navigateHome()
        
        XCTAssertNotNil(app.errorMessage, "Should have error message")
        XCTAssertTrue(app.errorMessage?.contains("No home family") ?? false, "Error should mention no home")
    }
    
    // MARK: - Set Home Family Tests
    
    func testSetHomeFamily() {
        app.setHomeFamily("KORPI 6")
        
        XCTAssertEqual(app.homeFamily, "KORPI 6", "Home should be set")
        XCTAssertTrue(app.canNavigateHome, "Should be able to navigate home")
    }
    
    func testSetHomeFamilyInvalid() {
        app.setHomeFamily("INVALID 999")
        
        XCTAssertNil(app.homeFamily, "Home should not be set for invalid ID")
    }
    
    func testSetHomeFamilyNormalization() {
        app.setHomeFamily("  korpi 6  ")
        
        XCTAssertEqual(app.homeFamily, "KORPI 6", "Home should be normalized")
    }
    
    // MARK: - PDF Mode Tests
    
    func testPDFModeToggle() {
        XCTAssertFalse(app.showPDFMode, "PDF mode should be off initially")
        
        app.showPDFMode = true
        XCTAssertTrue(app.showPDFMode, "PDF mode should be on")
        
        app.showPDFMode = false
        XCTAssertFalse(app.showPDFMode, "PDF mode should be off again")
    }
    
    // MARK: - Integration Tests
    
    func testCompleteNavigationWorkflow() async {
        // 1. Navigate to first family (sets home)
        app.navigateToFamily("KORPI 6", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.homeFamily, "KORPI 6")
        XCTAssertTrue(app.canNavigateHome)
        
        // 2. Navigate to second family
        app.navigateToFamily("HERLEVI 1", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.homeFamily, "HERLEVI 1")
        XCTAssertTrue(app.canNavigateBack)
        
        // 3. Navigate to third family
        app.navigateToFamily("SIKALA 3", updateHistory: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.navigationHistory.count, 3)
        
        // 4. Go back twice
        app.navigateBack()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        app.navigateBack()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.historyIndex, 0)
        XCTAssertEqual(app.currentFamilyIdInHistory, "KORPI 6")
        
        // 5. Go forward once
        app.navigateForward()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.currentFamilyIdInHistory, "HERLEVI 1")
        
        // 6. Navigate home (should go to SIKALA 3, the last one we set)
        app.navigateHome()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(app.currentFamily?.familyId, "SIKALA 3")
    }
}
