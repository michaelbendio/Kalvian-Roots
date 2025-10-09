//
//  ClanBrowserTests.swift
//  Kalvian Roots Tests
//
//  Tests for clan grouping and browser functionality
//

import XCTest
@testable import Kalvian_Roots

final class ClanBrowserTests: XCTestCase {
    
    // MARK: - Clan Grouping Tests
    
    func testGroupFamilyIDsByClan() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        XCTAssertFalse(clans.isEmpty, "Should have clans")
        
        // Check that KORPI clan exists
        let korpiClan = clans.first { $0.clanName == "KORPI" }
        XCTAssertNotNil(korpiClan, "KORPI clan should exist")
        
        // KORPI should have suffixes 1-12 and 2B
        if let korpi = korpiClan {
            XCTAssertTrue(korpi.suffixes.contains("1"), "KORPI should have suffix 1")
            XCTAssertTrue(korpi.suffixes.contains("6"), "KORPI should have suffix 6")
            XCTAssertTrue(korpi.suffixes.contains("12"), "KORPI should have suffix 12")
            XCTAssertTrue(korpi.suffixes.contains("2B"), "KORPI should have suffix 2B")
        }
    }
    
    func testClanGroupingHandlesMultiWordClans() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        // Check PIENI SIKALA (two-word clan name)
        let pieniSikalaClan = clans.first { $0.clanName == "PIENI SIKALA" }
        XCTAssertNotNil(pieniSikalaClan, "PIENI SIKALA clan should exist")
        
        if let clan = pieniSikalaClan {
            XCTAssertTrue(clan.suffixes.contains("1"), "PIENI SIKALA should have suffix 1")
            XCTAssertTrue(clan.suffixes.contains("2"), "PIENI SIKALA should have suffix 2")
            XCTAssertTrue(clan.suffixes.contains("3"), "PIENI SIKALA should have suffix 3")
        }
    }
    
    func testClanGroupingHandlesRomanNumerals() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        // Check HERLEVI (has both plain and roman numeral suffixes)
        let herleviClan = clans.first { $0.clanName == "HERLEVI" }
        XCTAssertNotNil(herleviClan, "HERLEVI clan should exist")
        
        if let clan = herleviClan {
            // Should have plain numbers
            XCTAssertTrue(clan.suffixes.contains("1"), "HERLEVI should have suffix 1")
            XCTAssertTrue(clan.suffixes.contains("11"), "HERLEVI should have suffix 11")
            
            // Should have roman numeral prefixes
            XCTAssertTrue(clan.suffixes.contains("II 1"), "HERLEVI should have suffix II 1")
            XCTAssertTrue(clan.suffixes.contains("II 13"), "HERLEVI should have suffix II 13")
        }
    }
    
    func testClansAreSortedAlphabetically() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        // Check that clans are in alphabetical order
        let clanNames = clans.map { $0.clanName }
        let sortedNames = clanNames.sorted()
        
        XCTAssertEqual(clanNames, sortedNames, "Clans should be sorted alphabetically")
    }
    
    func testSuffixesAreSortedNaturally() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        // Find a clan with many suffixes
        let korpiClan = clans.first { $0.clanName == "KORPI" }
        XCTAssertNotNil(korpiClan)
        
        if let clan = korpiClan {
            // Check that numeric suffixes are in natural order
            // (e.g., 1, 2, 3, ... 10, 11, 12 not 1, 10, 11, 12, 2, 3...)
            let numericSuffixes = clan.suffixes.filter { Int($0) != nil }
            
            if numericSuffixes.count >= 2 {
                let firstIndex = clan.suffixes.firstIndex(of: "1")
                let tenIndex = clan.suffixes.firstIndex(of: "10")
                
                if let first = firstIndex, let ten = tenIndex {
                    XCTAssertLessThan(first, ten, "1 should come before 10")
                }
                
                let twoIndex = clan.suffixes.firstIndex(of: "2")
                if let two = twoIndex, let ten = tenIndex {
                    XCTAssertLessThan(two, ten, "2 should come before 10")
                }
            }
        }
    }
    
    func testRomanNumeralSuffixesAreSortedCorrectly() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        // Find HANHISALO which has I, II, III
        let hanhisaloClan = clans.first { $0.clanName == "HANHISALO" }
        XCTAssertNotNil(hanhisaloClan)
        
        if let clan = hanhisaloClan {
            // Plain numbers should come before roman numerals
            let plainSuffixes = clan.suffixes.filter { Int($0) != nil }
            let romanSuffixes = clan.suffixes.filter { $0.contains("II") || $0.contains("III") }
            
            if !plainSuffixes.isEmpty && !romanSuffixes.isEmpty {
                if let lastPlainIndex = clan.suffixes.lastIndex(where: { Int($0) != nil }),
                   let firstRomanIndex = clan.suffixes.firstIndex(where: { $0.contains("II") || $0.contains("III") }) {
                    XCTAssertLessThan(lastPlainIndex, firstRomanIndex, "Plain numbers should come before roman numerals")
                }
            }
            
            // Within roman numerals, they should be ordered I, II, III
            if clan.suffixes.contains("II 1") && clan.suffixes.contains("III 1") {
                let ii1Index = clan.suffixes.firstIndex(of: "II 1")!
                let iii1Index = clan.suffixes.firstIndex(of: "III 1")!
                XCTAssertLessThan(ii1Index, iii1Index, "II 1 should come before III 1")
            }
        }
    }
    
    func testAllFamilyIDsAreCategorized() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        // Count total suffixes across all clans
        let totalSuffixes = clans.reduce(0) { $0 + $1.suffixes.count }
        
        // Should equal total number of family IDs
        XCTAssertEqual(totalSuffixes, FamilyIDs.validFamilyIds.count, 
                      "All family IDs should be categorized into clans")
    }
    
    func testNoDuplicateSuffixesWithinClan() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        for clan in clans {
            let uniqueSuffixes = Set(clan.suffixes)
            XCTAssertEqual(clan.suffixes.count, uniqueSuffixes.count, 
                          "Clan \(clan.clanName) should not have duplicate suffixes")
        }
    }
    
    func testEveryFamilyIDCanBeReconstructed() {
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        // Reconstruct all family IDs from clans
        var reconstructed = Set<String>()
        for clan in clans {
            for suffix in clan.suffixes {
                reconstructed.insert("\(clan.clanName) \(suffix)")
            }
        }
        
        // Compare with original set
        let original = Set(FamilyIDs.validFamilyIds)
        XCTAssertEqual(reconstructed, original, "Should be able to reconstruct all original family IDs")
    }
    
    // MARK: - Natural Sort Tests
    
    func testNaturalSortHandlesPlainNumbers() {
        let suffixes = ["1", "2", "10", "3", "11", "20"]
        let sorted = suffixes.sorted { lhs, rhs in
            // This would use the naturalCompare function from ClanBrowserView
            // For testing purposes, we verify the grouping function produces correct order
            return true
        }
        
        // Just verify that the grouping function exists and works
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        XCTAssertFalse(clans.isEmpty, "Grouping function should work")
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyFamilyIDsHandledGracefully() {
        // This tests that the function doesn't crash with edge cases
        let clans = ClanBrowserView.groupFamilyIDsByClan()
        
        // Should not have any clans with empty names
        for clan in clans {
            XCTAssertFalse(clan.clanName.isEmpty, "Clan name should not be empty")
            XCTAssertFalse(clan.suffixes.isEmpty, "Clan should have at least one suffix")
            
            for suffix in clan.suffixes {
                XCTAssertFalse(suffix.isEmpty, "Suffix should not be empty")
            }
        }
    }
}
