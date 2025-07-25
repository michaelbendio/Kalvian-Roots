//
//  Family.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation
import UniformTypeIdentifiers

/**
 * Family.swift - Core genealogical data structures
 *
 * Contains Family struct for Finnish genealogy data from Juuret Kälviällä.
 * Updated for AI parsing without Foundation Models Framework dependencies.
 */

/**
 * Complete family unit from Juuret Kälviällä genealogical text.
 *
 * Enhanced for cross-reference resolution and AI parsing.
 * Removed @Generable and @Guide annotations for direct AI prompting approach.
 */
struct Family: Hashable, Sendable {
    // MARK: - Core Family Data
    
    /// Family ID like 'KORPI 6' or 'ISO-PEITSO II 3'
    var familyId: String
    
    /// Source page numbers like ['105', '106']
    var pageReferences: [String]
    
    /// Father with vital dates and genealogical info
    var father: Person
    
    /// Mother with vital dates, may be nil
    var mother: Person?
    
    /// Additional spouses (II puoliso, III puoliso)
    var additionalSpouses: [Person]
    
    /// All children with birth dates and marriage info
    var children: [Person]
    
    /// Historical notes about migrations, occupations
    var notes: [String]
    
    /// Number from 'Lapsena kuollut N' notation
    var childrenDiedInfancy: Int?
    
    // MARK: - Initializers
    
    init(
        familyId: String,
        pageReferences: [String],
        father: Person,
        mother: Person? = nil,
        additionalSpouses: [Person] = [],
        children: [Person] = [],
        notes: [String] = [],
        childrenDiedInfancy: Int? = nil
    ) {
        self.familyId = familyId
        self.pageReferences = pageReferences
        self.father = father
        self.mother = mother
        self.additionalSpouses = additionalSpouses
        self.children = children
        self.notes = notes
        self.childrenDiedInfancy = childrenDiedInfancy
    }
    
    // MARK: - Computed Properties
    
    /// All persons in family for processing
    var allPersons: [Person] {
        var persons = [father]
        if let mother = mother {
            persons.append(mother)
        }
        persons.append(contentsOf: additionalSpouses)
        persons.append(contentsOf: children)
        return persons
    }
    
    /// All parents (father + mother + additional spouses)
    var allParents: [Person] {
        var parents = [father]
        if let mother = mother {
            parents.append(mother)
        }
        parents.append(contentsOf: additionalSpouses)
        return parents
    }
    
    /// Children with spouse info for cross-reference resolution
    var marriedChildren: [Person] {
        children.filter { $0.isMarried }
    }
    
    /// Children who need cross-reference resolution
    var childrenNeedingResolution: [Person] {
        children.filter { $0.needsCrossReferenceResolution }
    }
    
    /// Parents who need cross-reference resolution
    var parentsNeedingResolution: [Person] {
        allParents.filter { $0.needsCrossReferenceResolution }
    }
    
    /// Total count of persons needing cross-reference
    var totalCrossReferencesNeeded: Int {
        return parentsNeedingResolution.count + childrenNeedingResolution.count
    }
    
    /// Get primary marriage date for family
    var primaryMarriageDate: String? {
        return father.bestMarriageDate ?? mother?.bestMarriageDate
    }
    
    /// Get formatted page reference string
    var pageReferenceString: String {
        if pageReferences.count == 1 {
            return "page \(pageReferences[0])"
        } else {
            return "pages \(pageReferences.joined(separator: ", "))"
        }
    }
    
    // MARK: - Family Relationship Methods
    
    /// Parent names for Hiski birth queries
    func getParentNames(for child: Person) -> (father: String, mother: String?) {
        return (father.displayName, mother?.displayName)
    }
    
    /// Find a child by name (case-insensitive)
    func findChild(named name: String) -> Person? {
        return children.first { $0.name.lowercased() == name.lowercased() }
    }
    
    /// Find a parent by name (case-insensitive)
    func findParent(named name: String) -> Person? {
        return allParents.first { $0.name.lowercased() == name.lowercased() }
    }
    
    /// Check if a person is a child in this family
    func isChild(_ person: Person) -> Bool {
        return children.contains { $0.name.lowercased() == person.name.lowercased() }
    }
    
    /// Check if a person is a parent in this family
    func isParent(_ person: Person) -> Bool {
        return allParents.contains { $0.name.lowercased() == person.name.lowercased() }
    }
    
    // MARK: - Cross-Reference Enhancement
    
    /// Update family with enhanced person data from cross-references
    mutating func enhanceWithCrossReferences(_ enhancedPersons: [Person]) {
        // Update father
        if let enhanced = enhancedPersons.first(where: { $0.name.lowercased() == father.name.lowercased() }) {
            father = enhanced
        }
        
        // Update mother
        if let mother = mother,
           let enhanced = enhancedPersons.first(where: { $0.name.lowercased() == mother.name.lowercased() }) {
            self.mother = enhanced
        }
        
        // Update additional spouses
        for i in additionalSpouses.indices {
            if let enhanced = enhancedPersons.first(where: { $0.name.lowercased() == additionalSpouses[i].name.lowercased() }) {
                additionalSpouses[i] = enhanced
            }
        }
        
        // Update children
        for i in children.indices {
            if let enhanced = enhancedPersons.first(where: { $0.name.lowercased() == children[i].name.lowercased() }) {
                children[i] = enhanced
            }
        }
    }
    
    /// Create a copy with enhanced parent names for all children
    func withEnhancedParentNames() -> Family {
        var enhancedFamily = self
        
        // Add parent names to all children for Hiski queries
        for i in enhancedFamily.children.indices {
            enhancedFamily.children[i].fatherName = father.displayName
            enhancedFamily.children[i].motherName = mother?.displayName
        }
        
        return enhancedFamily
    }
    
    // MARK: - Validation
    
    /// Validate family structure for genealogical accuracy
    func validateStructure() -> [String] {
        var warnings: [String] = []
        
        if father.name.isEmpty {
            warnings.append("Father name is required")
        }
        
        if familyId.isEmpty {
            warnings.append("Family ID is required")
        }
        
        if pageReferences.isEmpty {
            warnings.append("Page references are required")
        }
        
        // Validate all persons in family
        for person in allPersons {
            let personWarnings = person.validateData()
            warnings.append(contentsOf: personWarnings.map { "\(person.displayName): \($0)" })
            
            if let asChildRef = person.asChildReference,
               !FamilyIDs.validFamilyIds.contains(asChildRef.uppercased()) {
                warnings.append("Invalid as_child reference: \(asChildRef) for \(person.name)")
            }
            
            if let asParentRef = person.asParentReference {
                if !FamilyIDs.validFamilyIds.contains(asParentRef.uppercased()) {
                    warnings.append("Invalid as_parent reference: \(asParentRef) for \(person.name)")
                }
            }
        }
        
        // Check for duplicate children names
        let childNames = children.map { $0.name.lowercased() }
        let uniqueNames = Set(childNames)
        if childNames.count != uniqueNames.count {
            warnings.append("Duplicate child names found")
        }
        
        // Validate family ID format
        if !FamilyIDs.validFamilyIds.contains(familyId.uppercased()) {
            warnings.append("Family ID '\(familyId)' not found in valid family IDs")
        }
        
        return warnings
    }
    
    /// Quick validation check for critical issues
    var isValid: Bool {
        return !father.name.isEmpty && !familyId.isEmpty && !pageReferences.isEmpty
    }
    
    // MARK: - Citation Support
    
    /// Generate citation data for this family
    func getCitationData() -> FamilyCitationData {
        return FamilyCitationData(
            familyId: familyId,
            pageReferences: pageReferences,
            father: father,
            mother: mother,
            additionalSpouses: additionalSpouses,
            children: children,
            notes: notes,
            childrenDiedInfancy: childrenDiedInfancy,
            primaryMarriageDate: primaryMarriageDate
        )
    }
    
    /// Get all persons who need Hiski queries
    func getPersonsForHiskiQueries() -> [Person] {
        return allPersons.filter { person in
            // Include persons with birth, marriage, or death dates
            return person.birthDate != nil ||
                   person.bestMarriageDate != nil ||
                   person.bestDeathDate != nil
        }
    }
    
    // MARK: - Cross-Reference Query Generation
    
    /// Generate cross-reference requests for all family members
    func generateCrossReferenceRequests() -> [CrossReferenceRequest] {
        var requests: [CrossReferenceRequest] = []
        
        // Parent as_child requests
        for parent in allParents {
            if let asChildRef = parent.asChildReference {
                requests.append(CrossReferenceRequest(
                    personName: parent.displayName,
                    birthDate: parent.birthDate,
                    asChildReference: asChildRef,
                    spouseName: nil,
                    marriageDate: nil,
                    requestType: .asChild
                ))
            }
        }
        
        // Children as_parent requests
        for child in children {
            if let asParentRef = child.asParentReference {
                requests.append(CrossReferenceRequest(
                    personName: child.displayName,
                    birthDate: child.birthDate,
                    asChildReference: nil,
                    spouseName: child.spouse,
                    marriageDate: child.bestMarriageDate,
                    requestType: .asParent
                ))
            }
        }
        
        // Spouse as_child requests (for married children)
        for child in marriedChildren {
            if let spouse = child.spouse {
                requests.append(CrossReferenceRequest(
                    personName: spouse,
                    birthDate: child.spouseBirthDate,
                    asChildReference: child.spouseParentsFamilyId,
                    spouseName: child.displayName,
                    marriageDate: child.bestMarriageDate,
                    requestType: .spouseAsChild
                ))
            }
        }
        
        return requests
    }
    
    // MARK: - Sample Data
    
    /// Create sample family for testing
    static func sampleFamily() -> Family {
        let father = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "09.09.1727",
            deathDate: "22.08.1812",
            marriageDate: "14.10.1750",
            spouse: "Brita Matint.",
            asChildReference: "KORPI 5"
        )
        
        let mother = Person(
            name: "Brita",
            patronymic: "Matint.",
            birthDate: "05.09.1731",
            deathDate: "11.07.1769",
            marriageDate: "14.10.1750",
            spouse: "Matti Erikinp.",
            asChildReference: "SIKALA 5"
        )
        
        let child1 = Person(
            name: "Maria",
            birthDate: "10.02.1752",
            marriageDate: "1773",
            spouse: "Elias Iso-Peitso",
            asParentReference: "ISO-PEITSO III 2"
        )
        
        let child2 = Person(
            name: "Kaarin",
            birthDate: "01.02.1753",
            deathDate: "17.04.1795"
        )
        
        return Family(
            familyId: "KORPI 6",
            pageReferences: ["105", "106"],
            father: father,
            mother: mother,
            additionalSpouses: [],
            children: [child1, child2],
            notes: ["Lapsena kuollut 4."],
            childrenDiedInfancy: 4
        )
    }
    
    /// Create test family with complex structure
    static func complexSampleFamily() -> Family {
        let father = Person(
            name: "Matti",
            patronymic: "Matinp.",
            birthDate: "22.12.1701",
            deathDate: "27.05.1764",
            marriageDate: "28.11.1725",
            spouse: "Brita Kustaant.",
            asChildReference: "HERLEVI 2"
        )
        
        let mother = Person(
            name: "Brita",
            patronymic: "Kustaant.",
            birthDate: "20.05.1699",
            deathDate: "25.11.1739",
            marriageDate: "28.11.1725",
            spouse: "Matti Matinp.",
            asChildReference: "RAHKONEN 3"
        )
        
        let additionalSpouse = Person(
            name: "Kaarin",
            patronymic: "Laurint.",
            birthDate: "1720",
            marriageDate: "21.12.1740",
            spouse: "Matti Matinp."
        )
        
        let child1 = Person(
            name: "Kustaa",
            birthDate: "22.08.1726",
            marriageDate: "1748",
            spouse: "Kaarin Riippa",
            asParentReference: "PIENI-PORKOLA 6"
        )
        
        let child2 = Person(
            name: "Juho",
            birthDate: "27.01.1744",
            marriageDate: "1765",
            spouse: "Anna Lassila",
            asParentReference: "PIENI-PORKOLA",
            noteMarkers: ["*"]
        )
        
        return Family(
            familyId: "PIENI-PORKOLA 5",
            pageReferences: ["268", "269"],
            father: father,
            mother: mother,
            additionalSpouses: [additionalSpouse],
            children: [child1, child2],
            notes: [
                "Talo on 1739 alkaen Pieni-Porkola.",
                "Juho kuoli 26.01.1767, leski Pirkola 8."
            ],
            childrenDiedInfancy: 1
        )
    }
}

// MARK: - Supporting Data Structures

/**
 * Citation data structure for generating Juuret Kälviällä citations
 */
struct FamilyCitationData {
    let familyId: String
    let pageReferences: [String]
    let father: Person
    let mother: Person?
    let additionalSpouses: [Person]
    let children: [Person]
    let notes: [String]
    let childrenDiedInfancy: Int?
    let primaryMarriageDate: String?
}

/**
 * Cross-reference request for family resolution
 */
struct CrossReferenceRequest {
    let personName: String        // "Matti Erikinp."
    let birthDate: String?        // "09.09.1727"
    let asChildReference: String? // "KORPI 5" (from {Korpi 5})
    let spouseName: String?       // "Brita Matint."
    let marriageDate: String?     // "14.10.1750"
    let requestType: CrossRefType // .asChild, .asParent, .spouseAsChild
}

/**
 * Type of cross-reference resolution needed
 */
enum CrossRefType {
    case asChild      // Find this person's parents' family
    case asParent     // Find this person's family where they're a parent
    case spouseAsChild // Find this person's spouse's parents' family
}

/**
 * Cross-reference response with confidence scoring
 */
struct CrossReferenceResponse {
    let resolvedFamilyId: String  // "KORPI 5"
    let confidence: Double        // 0.0 to 1.0
    let method: String           // "family_reference" or "birth_date_search"
    let reasons: [String]        // Match justifications
    let warnings: [String]      // Potential issues
}

// MARK: - Family IDs Extension

extension FamilyIDs {
    /// Check if a family ID is valid (case-insensitive)
    static func isValid(familyId: String) -> Bool {
        return validFamilyIds.contains(familyId.uppercased())
    }
    
    /// Get normalized family ID (uppercase, trimmed)
    static func normalize(familyId: String) -> String {
        return familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
