//
//  Person.swift
//  Kalvian Roots
//
//  Individual person with Finnish naming conventions and genealogical data
//

import Foundation

/**
 * Individual person with Finnish naming conventions and genealogical data.
 */
struct Person: Hashable, Sendable, Codable, Identifiable {
    // MARK: - Core Genealogical Data
    
    var name: String
    var patronymic: String?
    var birthDate: String? // format '22.12.1701'
    var deathDate: String?
    var marriageDate: String? // two or six digits (e.g., 04 or 23.05.19)
    var fullMarriageDate: String?
    var spouse: String?
    var asChild: String?
    var asParent: String?
    var familySearchId: String?
    var noteMarkers: [String] // Note markers like '*' or '**'
    var fatherName: String?    // for Hiski disambiguation
    var motherName: String?
    var spouseBirthDate: String? // spouse's as_child family
    var spouseParentsFamilyId: String?
    
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
    
    /// Best available marriage date (full date takes priority)
    var bestMarriageDate: String? {
        return fullMarriageDate ?? marriageDate
    }
    
    /// Check if person has spouse information
    var isMarried: Bool {
        return spouse != nil || marriageDate != nil || fullMarriageDate != nil
    }
    
    /// Check if person needs cross-reference resolution
    var needsCrossReferenceResolution: Bool {
        return asChild != nil || asParent != nil || spouse != nil
    }
    
    /// Check if person has parent information for Hiski queries
    var hasParentInfo: Bool {
        return fatherName != nil || motherName != nil
    }
    
    // MARK: - Initializer
    
    init(
        name: String,
        patronymic: String? = nil,
        birthDate: String? = nil,
        deathDate: String? = nil,
        marriageDate: String? = nil,
        fullMarriageDate: String? = nil,
        spouse: String? = nil,
        asChild: String? = nil,
        asParent: String? = nil,
        familySearchId: String? = nil,
        noteMarkers: [String] = [],
        fatherName: String? = nil,
        motherName: String? = nil,
        spouseBirthDate: String? = nil,
        spouseParentsFamilyId: String? = nil
    ) {
        self.name = name
        self.patronymic = patronymic
        self.birthDate = birthDate
        self.deathDate = deathDate
        self.marriageDate = marriageDate
        self.fullMarriageDate = fullMarriageDate
        self.spouse = spouse
        self.asChild = asChild
        self.asParent = asParent
        self.familySearchId = familySearchId
        self.noteMarkers = noteMarkers
        self.fatherName = fatherName
        self.motherName = motherName
        self.spouseBirthDate = spouseBirthDate
        self.spouseParentsFamilyId = spouseParentsFamilyId
    }
    
    // MARK: - Helper Methods
    
    /// Get formatted display date (converts DD.MM.YYYY to readable format)
    func getFormattedDate(_ date: String?) -> String? {
        guard let date = date else { return nil }
        // This would call DateFormatter.formatGenealogyDate(date) in the actual implementation
        return date
    }
    
    /// Validate person data and return warnings
    func validateData() -> [String] {
        var warnings: [String] = []
        
        if name.isEmpty {
            warnings.append("Person name is required")
        }
        
        if let birthDate = birthDate, !isValidDateFormat(birthDate) {
            warnings.append("Unusual birth date format: \(birthDate)")
        }
        
        if let deathDate = deathDate, !isValidDateFormat(deathDate) {
            warnings.append("Unusual death date format: \(deathDate)")
        }
        
        return warnings
    }
    
    private func isValidDateFormat(_ date: String) -> Bool {
        // Check for DD.MM.YYYY format
        let pattern = #"^\d{1,2}\.\d{1,2}\.\d{4}$"#
        return date.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Person Extensions

extension Person {
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
}

