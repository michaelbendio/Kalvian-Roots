//
//  Person.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation

/**
 * Person.swift - Individual genealogical person data
 *
 * Individual person with Finnish naming conventions and genealogical data.
 * Updated for AI parsing without Foundation Models Framework dependencies.
 */

/**
 * Individual person with Finnish naming conventions and genealogical data.
 *
 * Enhanced for cross-reference resolution and AI parsing.
 */
struct Person: Hashable, Sendable, Codable, Identifiable {
    // MARK: - Core Genealogical Data
    
    /// Finnish given name like 'Matti', 'Brita'
    var name: String
    
    /// Patronymic like 'Erikinp.' (Erik's son), 'Matint.' (Matti's daughter)
    var patronymic: String?
    
    /// Birth date in format '22.12.1701'
    var birthDate: String?
    
    /// Death date in format '22.08.1812'
    var deathDate: String?
    
    /// Marriage date like '14.10.1750' or '∞ 51'
    var marriageDate: String?
    
    /// Spouse name with patronymic like 'Brita Matint.'
    var spouse: String?
    
    /// Family reference from {family_id} notation where person is a child
    var asChildReference: String?
    
    /// Family where person appears as parent
    var asParentReference: String?
    
    /// FamilySearch ID from <ID> notation, may be nil
    var familySearchId: String?
    
    /// Note markers like '*' or '**'
    var noteMarkers: [String]
    
    // MARK: - Cross-Reference Enhancement Fields (NEW)
    
    /// Father's name for Hiski birth record disambiguation
    var fatherName: String?
    
    /// Mother's name for Hiski birth record disambiguation
    var motherName: String?
    
    /// Enhanced death date from as_parent family (more complete than original)
    var enhancedDeathDate: String?
    
    /// Enhanced marriage date from as_parent family (full date vs partial)
    var enhancedMarriageDate: String?
    
    /// Spouse's birth date from spouse's as_child family
    var spouseBirthDate: String?
    
    /// Spouse's parents' family ID for complete spouse documentation
    var spouseParentsFamilyId: String?
    
    // MARK: - Initializers
    
    init(
        name: String,
        patronymic: String? = nil,
        birthDate: String? = nil,
        deathDate: String? = nil,
        marriageDate: String? = nil,
        spouse: String? = nil,
        asChildReference: String? = nil,
        asParentReference: String? = nil,
        familySearchId: String? = nil,
        noteMarkers: [String] = [],
        fatherName: String? = nil,
        motherName: String? = nil,
        enhancedDeathDate: String? = nil,
        enhancedMarriageDate: String? = nil,
        spouseBirthDate: String? = nil,
        spouseParentsFamilyId: String? = nil
    ) {
        self.name = name
        self.patronymic = patronymic
        self.birthDate = birthDate
        self.deathDate = deathDate
        self.marriageDate = marriageDate
        self.spouse = spouse
        self.asChildReference = asChildReference
        self.asParentReference = asParentReference
        self.familySearchId = familySearchId
        self.noteMarkers = noteMarkers
        self.fatherName = fatherName
        self.motherName = motherName
        self.enhancedDeathDate = enhancedDeathDate
        self.enhancedMarriageDate = enhancedMarriageDate
        self.spouseBirthDate = spouseBirthDate
        self.spouseParentsFamilyId = spouseParentsFamilyId
    }
    
    // MARK: - Computed Properties
    
    /// Full name with patronymic for display
    var displayName: String {
        if let patronymic = patronymic {
            return "\(name) \(patronymic)"
        }
        return name
    }
    
    var id: String {
        let patronymicPart = patronymic ?? ""
        let birthPart = birthDate ?? ""
        return "\(name)-\(patronymicPart)-\(birthPart)"
    }
    
    /// Check if person needs cross-reference resolution
    var needsCrossReferenceResolution: Bool {
        return asChildReference != nil || asParentReference != nil || spouse != nil
    }
    
    /// Best available death date (enhanced takes priority)
    var bestDeathDate: String? {
        return enhancedDeathDate ?? deathDate
    }
    
    /// Best available marriage date (enhanced takes priority)
    var bestMarriageDate: String? {
        return enhancedMarriageDate ?? marriageDate
    }
    
    /// Check if person has spouse information
    var isMarried: Bool {
        return spouse != nil || marriageDate != nil || enhancedMarriageDate != nil
    }
    
    /// Check if person has parent information for Hiski queries
    var hasParentInfo: Bool {
        return fatherName != nil || motherName != nil
    }
    
    /// Get formatted display date (converts DD.MM.YYYY to readable format)
    func getFormattedDate(_ date: String?) -> String? {
        guard let date = date else { return nil }
        return DateFormatter.formatGenealogyDate(date)
    }
    
    // MARK: - Cross-Reference Enhancement
    
    /// Update person with data from their as_parent family
    mutating func enhanceWithAsParentData(deathDate: String? = nil, marriageDate: String? = nil) {
        if let deathDate = deathDate {
            self.enhancedDeathDate = deathDate
        }
        if let marriageDate = marriageDate {
            self.enhancedMarriageDate = marriageDate
        }
    }
    
    /// Update person with spouse information from cross-reference
    mutating func enhanceWithSpouseData(birthDate: String? = nil, parentsFamilyId: String? = nil) {
        if let birthDate = birthDate {
            self.spouseBirthDate = birthDate
        }
        if let parentsFamilyId = parentsFamilyId {
            self.spouseParentsFamilyId = parentsFamilyId
        }
    }
    
    /// Update person with parent names for Hiski disambiguation
    mutating func enhanceWithParentNames(father: String? = nil, mother: String? = nil) {
        if let father = father {
            self.fatherName = father
        }
        if let mother = mother {
            self.motherName = mother
        }
    }
    
    // MARK: - Validation
    
    /// Validate person data and return warnings
    func validateData() -> [String] {
        var warnings: [String] = []
        
        if name.isEmpty {
            warnings.append("Person name is required")
        }
        
        if let birthDate = birthDate,
           !isValidDateFormat(birthDate) {
            warnings.append("Unusual birth date format: \(birthDate)")
        }
        
        if let deathDate = deathDate,
           !isValidDateFormat(deathDate) {
            warnings.append("Unusual death date format: \(deathDate)")
        }
        
        if let asChildRef = asChildReference,
           !FamilyIDs.validFamilyIds.contains(asChildRef.uppercased()) {
            warnings.append("Invalid as_child reference: \(asChildRef)")
        }
        
        if let asParentRef = asParentReference,
           !FamilyIDs.validFamilyIds.contains(asParentRef.uppercased()) {
            warnings.append("Invalid as_parent reference: \(asParentRef)")
        }
        
        return warnings
    }
    
    /// Check if date string is in valid format (DD.MM.YYYY or partial)
    private func isValidDateFormat(_ date: String) -> Bool {
        // Allow DD.MM.YYYY format
        if date.matches(regex: #"^\d{1,2}\.\d{1,2}\.\d{4}$"#) {
            return true
        }
        
        // Allow partial dates like "1727" or "∞ 51"
        if date.matches(regex: #"^\d{4}$"#) || date.contains("∞") {
            return true
        }
        
        return false
    }
    
    // MARK: - Name Equivalence Support
    
    /// Check if this person could be the same as another person (for cross-reference resolution)
    func couldBeSamePerson(as other: Person, allowingNameEquivalences: [String: String] = [:]) -> Bool {
        // Birth date must match exactly (most reliable identifier)
        guard birthDate == other.birthDate else { return false }
        
        // Check name equivalence
        let nameMatch = name.lowercased() == other.name.lowercased() ||
                       allowingNameEquivalences[name.lowercased()] == other.name.lowercased() ||
                       allowingNameEquivalences[other.name.lowercased()] == name.lowercased()
        
        guard nameMatch else { return false }
        
        // Check patronymic if both have it
        if let myPatronymic = patronymic, let otherPatronymic = other.patronymic {
            return myPatronymic.lowercased() == otherPatronymic.lowercased()
        }
        
        // If only one has patronymic, still could be same person
        return true
    }
    
    // MARK: - Hiski Query Support
    
    /// Generate parameters for Hiski birth query
    func getHiskiBirthQueryParams() -> (childName: String, birthDate: String?, fatherName: String?, motherName: String?) {
        return (
            childName: displayName,
            birthDate: birthDate,
            fatherName: fatherName,
            motherName: motherName
        )
    }
    
    /// Generate parameters for Hiski marriage query
    func getHiskiMarriageQueryParams() -> (spouse1: String, spouse2: String?, marriageDate: String?) {
        return (
            spouse1: displayName,
            spouse2: spouse,
            marriageDate: bestMarriageDate
        )
    }
    
    /// Generate parameters for Hiski death query
    func getHiskiDeathQueryParams() -> (personName: String, deathDate: String?) {
        return (
            personName: displayName,
            deathDate: bestDeathDate
        )
    }
}

// MARK: - Extensions

extension String {
    /// Check if string matches a regex pattern
    func matches(regex pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: count)
        return regex.firstMatch(in: self, range: range) != nil
    }
}

extension DateFormatter {
    /// Shared formatter for genealogical dates
    static let genealogicalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()
    
    /// Convert DD.MM.YYYY to readable format like "9 September 1727"
    static func formatGenealogyDate(_ dateString: String) -> String? {
        let parts = dateString.components(separatedBy: ".")
        guard parts.count == 3,
              let day = Int(parts[0]),
              let month = Int(parts[1]),
              let year = Int(parts[2]) else {
            return nil
        }
        
        let months = ["", "January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        
        guard month > 0 && month <= 12 else { return nil }
        
        return "\(day) \(months[month]) \(year)"
    }
}

