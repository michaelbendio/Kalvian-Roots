//
//  Family.swift
//  Kalvian Roots
//
//  Complete family unit from Juuret Kälviällä genealogical text
//

import Foundation

/**
 * Represents a couple with their children
 */
struct Couple: Hashable, Sendable, Codable {
    /// Husband in the couple
    var husband: Person
    
    /// Wife in the couple
    var wife: Person
    
    /// Marriage date for this couple
    var marriageDate: String?
    
    /// Children from this couple
    var children: [Person]
    
    /// Number of children who died in infancy from this couple
    var childrenDiedInfancy: Int?
    
    /// Notes specific to this couple
    var coupleNotes: [String]
    
    init(husband: Person, wife: Person, marriageDate: String? = nil,
         children: [Person] = [], childrenDiedInfancy: Int? = nil,
         coupleNotes: [String] = []) {
        self.husband = husband
        self.wife = wife
        self.marriageDate = marriageDate
        self.children = children
        self.childrenDiedInfancy = childrenDiedInfancy
        self.coupleNotes = coupleNotes
    }
}

/**
 * Complete family unit from Juuret Kälviällä genealogical text.
 * A family consists of one or more couples and their respective children.
 */
struct Family: Hashable, Sendable, Codable {
    // MARK: - Core Family Data
    
    /// Family ID like 'PIENI-PORKOLA 5' or 'KORPI 6'
    var familyId: String
    
    /// Source page numbers like ['268', '269']
    var pageReferences: [String]
    
    /// All couples in this family unit
    /// Even a simple family has one couple
    var couples: [Couple]
    
    /// General family notes
    var notes: [String]
    
    /// Note marker definitions (e.g., "*": "Juho kuoli 26.01.1767, leski Pirkola 8.")
    var noteDefinitions: [String: String]
    
    // MARK: - Convenience Accessors
    
    /// Primary couple (first couple in the family)
    var primaryCouple: Couple? {
        return couples.first
    }
    
    /// Primary father (husband of first couple)
    var father: Person? {
        return couples.first?.husband
    }
    
    /// Primary mother (wife of first couple)
    var mother: Person? {
        return couples.first?.wife
    }
    
    /// Children of the primary couple
    var children: [Person] {
        return couples.first?.children ?? []
    }
    
    // MARK: - FIXED: Missing Computed Properties for Backward Compatibility
    
    /// All parents across all couples (for cross-reference resolution)
    var allParents: [Person] {
        var parents: [Person] = []
        for couple in couples {
            parents.append(couple.husband)
            parents.append(couple.wife)
        }
        return parents
    }
    
    /// All children who are married (have spouse information)
    var marriedChildren: [Person] {
        var married: [Person] = []
        for couple in couples {
            for child in couple.children {
                if child.isMarried {
                    married.append(child)
                }
            }
        }
        return married
    }
    
    /// Additional spouses (all spouses beyond the first couple)
    var additionalSpouses: [Person] {
        guard couples.count > 1 else { return [] }
        var spouses: [Person] = []
        for couple in couples.dropFirst() {
            spouses.append(couple.wife) // Assuming husband is constant, wife changes
        }
        return spouses
    }
    
    /// All children who died in infancy across all couples
    var childrenDiedInfancy: Int? {
        let total = couples.compactMap { $0.childrenDiedInfancy }.reduce(0, +)
        return total > 0 ? total : nil
    }
    
    // MARK: - Computed Properties
    
    /// Get formatted page reference string
    var pageReferenceString: String {
        if pageReferences.count == 1 {
            return "page \(pageReferences[0])"
        } else {
            return "pages \(pageReferences.joined(separator: ", "))"
        }
    }
    
    /// Check if family structure is valid
    var isValid: Bool {
        return !familyId.isEmpty && !pageReferences.isEmpty && !couples.isEmpty
    }
    
    // MARK: - Helper Methods
    
    /// Find a person across all couples
    func findPerson(named name: String) -> Person? {
        for couple in couples {
            if couple.husband.name.lowercased() == name.lowercased() {
                return couple.husband
            }
            if couple.wife.name.lowercased() == name.lowercased() {
                return couple.wife
            }
            if let child = couple.children.first(where: { $0.name.lowercased() == name.lowercased() }) {
                return child
            }
        }
        return nil
    }
    
    /// Get all unique persons in the family
    var allPersons: [Person] {
        var persons: Set<String> = []
        var result: [Person] = []
        
        for couple in couples {
            if !persons.contains(couple.husband.name) {
                persons.insert(couple.husband.name)
                result.append(couple.husband)
            }
            if !persons.contains(couple.wife.name) {
                persons.insert(couple.wife.name)
                result.append(couple.wife)
            }
            for child in couple.children {
                if !persons.contains(child.name) {
                    persons.insert(child.name)
                    result.append(child)
                }
            }
        }
        
        return result
    }
    
    /// Find which couple a child belongs to
    func findCoupleForChild(_ childName: String) -> Couple? {
        for couple in couples {
            if couple.children.contains(where: { $0.name.lowercased() == childName.lowercased() }) {
                return couple
            }
        }
        return nil
    }
    
    /// Get parent names for a specific child (for Hiski queries)
    func getParentNames(for child: Person) -> (father: String, mother: String?)? {
        if let couple = findCoupleForChild(child.name) {
            return (couple.husband.displayName, couple.wife.displayName)
        }
        return nil
    }
    
    // MARK: - Validation
    
    /// Validate family structure for genealogical accuracy
    func validateStructure() -> [String] {
        var warnings: [String] = []
        
        if familyId.isEmpty {
            warnings.append("Family ID is required")
        }
        
        if pageReferences.isEmpty {
            warnings.append("Page references are required")
        }
        
        if couples.isEmpty {
            warnings.append("At least one couple is required")
        }
        
        // Validate each couple
        for (index, couple) in couples.enumerated() {
            if couple.husband.name.isEmpty {
                warnings.append("Couple \(index + 1): Husband name is required")
            }
            if couple.wife.name.isEmpty {
                warnings.append("Couple \(index + 1): Wife name is required")
            }
            
            // Check for duplicate child names within couple
            let childNames = couple.children.map { $0.name.lowercased() }
            let uniqueNames = Set(childNames)
            if childNames.count != uniqueNames.count {
                warnings.append("Couple \(index + 1): Duplicate child names found")
            }
        }
        
        return warnings
    }
    
    // MARK: - Initializers
    
    /// Simple family with one couple
    init(familyId: String,
         pageReferences: [String],
         husband: Person,
         wife: Person,
         marriageDate: String? = nil,
         children: [Person] = [],
         childrenDiedInfancy: Int? = nil,
         notes: [String] = [],
         noteDefinitions: [String: String] = [:]) {
        
        let couple = Couple(
            husband: husband,
            wife: wife,
            marriageDate: marriageDate,
            children: children,
            childrenDiedInfancy: childrenDiedInfancy,
            coupleNotes: []
        )
        
        self.familyId = familyId
        self.pageReferences = pageReferences
        self.couples = [couple]
        self.notes = notes
        self.noteDefinitions = noteDefinitions
    }
    
    /// Complex family with multiple couples
    init(familyId: String,
         pageReferences: [String],
         couples: [Couple],
         notes: [String] = [],
         noteDefinitions: [String: String] = [:]) {
        
        self.familyId = familyId
        self.pageReferences = pageReferences
        self.couples = couples
        self.notes = notes
        self.noteDefinitions = noteDefinitions
    }
    
    // MARK: - Sample Families for Testing and Debugging

    static func sampleFamily() -> Family {
        let husband = Person(name: "Matti Erikinp.", patronymic: nil, birthDate: "10.02.1725", deathDate: "18.09.1802", noteMarkers: [])
        let wife = Person(name: "Maria Jaakont.", patronymic: nil, birthDate: "12.04.1727", deathDate: "14.07.1798", noteMarkers: [])
        let children = [
            Person(name: "Maria", patronymic: nil, birthDate: "10.02.1752", deathDate: nil, noteMarkers: []),
            Person(name: "Erkki", patronymic: nil, birthDate: "09.03.1755", deathDate: nil, noteMarkers: []),
            Person(name: "Helena", patronymic: nil, birthDate: "23.05.1757", deathDate: nil, noteMarkers: [])
        ]
        let couple = Couple(husband: husband, wife: wife, marriageDate: "1749", children: children, coupleNotes: [])
        return Family(
            familyId: "KORPI 6",
            pageReferences: ["105", "106"],
            couples: [couple],
            notes: ["Perhe muutti Ylivieskaan 1760-luvulla."],
            noteDefinitions: [:]
        )
    }

    static func complexSampleFamily() -> Family {
        let husband1 = Person(name: "Jaakko Jaakonp.", patronymic: nil, birthDate: "01.07.1698", deathDate: "31.08.1735", noteMarkers: [])
        let wife1 = Person(name: "Helena Mikont.", patronymic: nil, birthDate: "15.09.1702", deathDate: nil, noteMarkers: [])
        let children1 = [
            Person(name: "Maria", patronymic: nil, birthDate: "27.03.1726", deathDate: nil, noteMarkers: []),
            Person(name: "Jaakko", patronymic: nil, birthDate: "11.07.1728", deathDate: nil, noteMarkers: []),
            Person(name: "Antti", patronymic: nil, birthDate: "09.04.1731", deathDate: nil, noteMarkers: [])
        ]
        let couple1 = Couple(husband: husband1, wife: wife1, marriageDate: "1725", children: children1, coupleNotes: [])
        let husband2 = Person(name: "Jaakko Jaakonp.", patronymic: nil, birthDate: "11.07.1728", deathDate: nil, noteMarkers: [])
        let wife2 = Person(name: "Anna Matint.", patronymic: nil, birthDate: "18.02.1735", deathDate: nil, noteMarkers: [])
        let children2 = [
            Person(name: "Helena", patronymic: nil, birthDate: "25.05.1757", deathDate: nil, noteMarkers: [])
        ]
        let couple2 = Couple(husband: husband2, wife: wife2, marriageDate: "1756", children: children2, coupleNotes: [])
        return Family(
            familyId: "HYYPPÄ 5",
            pageReferences: ["369", "370"],
            couples: [couple1, couple2],
            notes: ["Tässä perheessä useita ristiinviittauksia."],
            noteDefinitions: [:]
        )
    }
}
