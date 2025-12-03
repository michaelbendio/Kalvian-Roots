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
    
    // Full marriage date from their asParent family
    var fullMarriageDate: String?
    
    /// Children from this couple
    var children: [Person]
    
    /// Number of children who died in infancy from this couple
    var childrenDiedInfancy: Int?
    
    /// Notes specific to this couple
    var coupleNotes: [String]
    
    init(husband: Person, wife: Person, marriageDate: String? = nil,
         fullMarriageDate: String? = nil,
         children: [Person] = [], childrenDiedInfancy: Int? = nil,
         coupleNotes: [String] = []) {
        self.husband = husband
        self.wife = wife
        self.marriageDate = marriageDate
        self.fullMarriageDate = fullMarriageDate
        self.children = children
        self.childrenDiedInfancy = childrenDiedInfancy
        self.coupleNotes = coupleNotes
    }
}

/**
 * Complete family unit from Juuret Kälviällä genealogical text.
 * A family consists of one or more couples and their respective children.
 */
public struct Family: Hashable, Sendable, Codable {
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
    
    // MARK: - Computed Properties for Cross-Reference Resolution
    
    /// All parents across all couples (for cross-reference resolution)
    var allParents: [Person] {
        var parents: [Person] = []
        for couple in couples {
            parents.append(couple.husband)
            parents.append(couple.wife)
        }
        return parents
    }
    
    /// All children across all couples who are married (have spouse information)
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
    
    /// Total children who died in infancy across all couples
    var totalChildrenDiedInfancy: Int {
        return couples.compactMap { $0.childrenDiedInfancy }.reduce(0, +)
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
    
    /// Full family with multiple couples
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
}

// MARK: - Sample Data Extensions

extension Family {
    /// Create sample family for testing
    static func sampleFamily() -> Family {
        let father = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "15.03.1723",
            deathDate: "12.11.1798",
            noteMarkers: []
        )
        
        let mother = Person(
            name: "Brita",
            patronymic: "Jaakont.",
            birthDate: "22.08.1731",
            deathDate: "05.07.1805",
            noteMarkers: []
        )
        
        let child1 = Person(
            name: "Maria",
            patronymic: "Matint.",
            birthDate: "18.05.1751",
            marriageDate: "73",
            spouse: "Juho Juhonp.",
            asParent: "KORPI 8",
            noteMarkers: []
        )
        
        let child2 = Person(
            name: "Erik",
            patronymic: "Matinp.",
            birthDate: "03.09.1753",
            noteMarkers: []
        )
        
        return Family(
            familyId: "SAMPLE 1",
            pageReferences: ["105", "106"],
            husband: father,
            wife: mother,
            marriageDate: "1750",
            children: [child1, child2]
        )
    }
    
    /// Create complex sample family with multiple spouses for testing
    static func complexSampleFamily() -> Family {
        let husband = Person(
            name: "Jaakko",
            patronymic: "Jaakonp.",
            birthDate: "09.10.1726",
            deathDate: "07.03.1789",
            asChild: "HYYPPÄ 5",
            noteMarkers: []
        )
        
        let firstWife = Person(
            name: "Maria",
            patronymic: "Jaakont.",
            birthDate: "02.03.1733",
            deathDate: "18.04.1753",
            asChild: "PIETILÄ 7",
            noteMarkers: []
        )
        
        let secondWife = Person(
            name: "Brita",
            patronymic: "Eliant.",
            birthDate: "11.01.1732",
            deathDate: "31.03.1767",
            asChild: "TIKKANEN 5",
            noteMarkers: []
        )
        
        let child1 = Person(
            name: "Maria",
            birthDate: "27.03.1763",
            marriageDate: "82",
            spouse: "Matti Korpi",
            asParent: "KORPI 9",
            noteMarkers: []
        )
        
        let child2 = Person(
            name: "Brita",
            birthDate: "11.02.1766",
            marriageDate: "86",
            spouse: "Henrik Karhulahti",
            asParent: "ISO-HYYPPÄ 10",
            noteMarkers: []
        )
        
        let primaryCouple = Couple(
            husband: husband,
            wife: firstWife,
            marriageDate: "08.10.1752",
            children: [],
            childrenDiedInfancy: nil,
            coupleNotes: []
        )
        
        let secondCouple = Couple(
            husband: husband,
            wife: secondWife,
            marriageDate: "06.10.1754",
            children: [child1, child2],
            childrenDiedInfancy: nil,
            coupleNotes: []
        )
        
        return Family(
            familyId: "HYYPPÄ 6",
            pageReferences: ["370"],
            couples: [primaryCouple, secondCouple],
            notes: ["Maria kuoli 1784 ja lapsi samana vuonna."],
            noteDefinitions: [:]
        )
    }
}

extension Family {
    /**
     * Find the spouse of a given person in this family
     * This method looks through couples to find who the person is married to
     *
     * @param personName The name of the person whose spouse we want to find
     * @return The spouse Person if found, nil if the person is not found or has no spouse in this family
     */
    func findSpouse(for personName: String) -> Person? {
        let lowercaseName = personName.lowercased()
        
        for couple in couples {
            if couple.husband.name.lowercased() == lowercaseName {
                return couple.wife
            } else if couple.wife.name.lowercased() == lowercaseName {
                return couple.husband
            }
        }
        return nil
    }
}
