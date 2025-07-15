//
//  Person.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation
import FoundationModels

/**
 * Person.swift - Individual genealogical person data
 *
 * Individual person with Finnish naming conventions and genealogical data.
 * Phase 2: Using Foundation Models @Generable for structured person extraction!
 */

/**
 * Individual person with Finnish naming conventions and genealogical data.
 *
 * Foundation Models @Generable: Enables structured person extraction with @Guide descriptions
 * for Finnish genealogical patterns and naming conventions.
 */
@Generable
struct Person: Hashable, Sendable {
    @Guide(description: "Finnish given name like 'Matti', 'Brita'")
    var name: String
    
    @Guide(description: "Patronymic like 'Erikinp.' (Erik's son), 'Matint.' (Matti's daughter)")
    var patronymic: String?
    
    @Guide(description: "Birth date in format '22.12.1701'")
    var birthDate: String?
    
    @Guide(description: "Death date in format '22.08.1812'")
    var deathDate: String?
    
    @Guide(description: "Marriage date like '14.10.1750' or '∞ 51'")
    var marriageDate: String?
    
    @Guide(description: "Spouse name with patronymic like 'Brita Matint.'")
    var spouse: String?
    
    @Guide(description: "Family reference from {family_id} notation")
    var asChildReference: String?
    
    @Guide(description: "Family where person appears as parent")
    var asParentReference: String?
    
    @Guide(description: "FamilySearch ID from <ID> notation, may be nil")
    var familySearchId: String?
    
    @Guide(description: "Note markers like '*' or '**'")
    var noteMarkers: [String]
    
    @Guide(description: "Father's name for birth record disambiguation")
    var fatherName: String?
    
    @Guide(description: "Mother's name for birth record disambiguation")
    var motherName: String?
    
    // MARK: - Initializer
    
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
        motherName: String? = nil
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
    }
    
    // MARK: - Computed Properties
    
    /// Full name with patronymic for display
    var displayName: String {
        if let patronymic = patronymic {
            return "\(name) \(patronymic)"
        }
        return name
    }
    
    /// Check if person needs cross-reference resolution
    var needsCrossReferenceResolution: Bool {
        return asChildReference != nil || asParentReference != nil || spouse != nil
    }
    
    // MARK: - Methods
    
    /// Validate person data
    func validateData() -> [String] {
        var warnings: [String] = []
        
        if name.isEmpty {
            warnings.append("Person name is required")
        }
        
        if let birthDate = birthDate,
           !birthDate.contains(".") && !birthDate.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
            warnings.append("Unusual birth date format: \(birthDate)")
        }
        
        return warnings
    }
}
