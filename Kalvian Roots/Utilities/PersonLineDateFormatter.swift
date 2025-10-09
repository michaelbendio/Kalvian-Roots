//
//  PersonLineDateFormatter.swift
//  Kalvian Roots
//
// For use in the person line UI
//
//  Created by Michael Bendio on 10/8/25.
//

import Foundation

/**
 * Utility for formatting enhanced dates with brown brackets
 *
 * Phase 3 Implementation:
 * - Single date: [19.10.1846]
 * - Date range: [03.03.1759-03.05.1809]
 * - Death date with prefix: [d. 19.10.1846]
 */
struct PersonLineDateFormatter {
    
    /**
     * Format a single enhanced date with brackets
     *
     * Example: "19.10.1846" → "[19.10.1846]"
     */
    static func formatSingleDate(_ date: String) -> String {
        return "[\(date)]"
    }
    
    /**
     * Format a date range with brackets
     *
     * Example: birth "03.03.1759", death "03.05.1809" → "[03.03.1759-03.05.1809]"
     */
    static func formatDateRange(birth: String, death: String) -> String {
        return "[\(birth)-\(death)]"
    }
    
    /**
     * Format a death date with 'd.' prefix and brackets
     *
     * Example: "19.10.1846" → "[d. 19.10.1846]"
     */
    static func formatDeathDate(_ date: String) -> String {
        return "[d. \(date)]"
    }
    
    /**
     * Format a full marriage date with brackets
     *
     * Example: "23.11.1778" → "[23.11.1778]"
     */
    static func formatMarriageDate(_ date: String) -> String {
        return "[\(date)]"
    }
    
    /**
     * Check if a date is a full 8-digit date (DD.MM.YYYY)
     */
    static func isFullDate(_ date: String) -> Bool {
        let components = date.components(separatedBy: ".")
        return components.count == 3 && components[2].count == 4
    }
    
    /**
     * Check if a date is a 2-digit year (like "78")
     */
    static func isTwoDigitYear(_ date: String) -> Bool {
        return date.count == 2 && Int(date) != nil
    }
    
    /**
     * Expand a 2-digit marriage year to full year
     *
     * Example: "78" with parent birth year 1727 → "1778"
     */
    static func expandTwoDigitYear(_ twoDigit: String, parentBirthYear: Int) -> String {
        guard let year = Int(twoDigit) else { return twoDigit }
        
        // Children typically marry 20-40 years after parent's birth
        let expectedCentury = (parentBirthYear + 20) / 100
        let expandedYear = (expectedCentury * 100) + year
        
        return String(expandedYear)
    }
}

// MARK: - Tests

#if DEBUG
extension PersonLineDateFormatter {
    static func runTests() {
        // Test single date formatting
        assert(formatSingleDate("19.10.1846") == "[19.10.1846]", "Single date formatting failed")
        
        // Test date range formatting
        assert(formatDateRange(birth: "03.03.1759", death: "03.05.1809") == "[03.03.1759-03.05.1809]", "Date range formatting failed")
        
        // Test death date formatting
        assert(formatDeathDate("19.10.1846") == "[d. 19.10.1846]", "Death date formatting failed")
        
        // Test marriage date formatting
        assert(formatMarriageDate("23.11.1778") == "[23.11.1778]", "Marriage date formatting failed")
        
        // Test full date detection
        assert(isFullDate("23.11.1778") == true, "Full date detection failed")
        assert(isFullDate("78") == false, "Two-digit date detection failed")
        
        // Test two-digit year detection
        assert(isTwoDigitYear("78") == true, "Two-digit year detection failed")
        assert(isTwoDigitYear("1778") == false, "Four-digit year detection failed")
        
        // Test year expansion
        assert(expandTwoDigitYear("78", parentBirthYear: 1727) == "1778", "Year expansion failed")
        assert(expandTwoDigitYear("04", parentBirthYear: 1760) == "1804", "Year expansion for 1800s failed")
        
        print("✅ All PersonLineDateFormatter tests passed")
    }
}
#endif
