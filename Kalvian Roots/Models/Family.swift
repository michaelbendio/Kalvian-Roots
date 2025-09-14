//
//  Family.swift
//  Kalvian Roots
//
//  Family data structure for Finnish genealogical records
//

import Foundation

/**
 * Family represents a genealogical family unit with couples and their children
 * Based on Finnish genealogical record format from Juuret Kälviällä
 */
struct Family: Hashable, Sendable, Codable, Identifiable {
    // MARK: - Core Properties
    
    /// Unique family identifier like "KORPI 5" or "VÄHÄ-HYYPPÄ 7"
    var familyId: String
    
    /// Page references from the source book
    var pageReferences: [String]
    
    /// Couples in this family (primary couple + additional spouses)
    var couples: [Couple]
    
    /// General notes about the family
    var notes: [String]
    
    /// Note definitions for symbols like * or **
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
        guard let couple = findCoupleForChild(child.name) else { return nil }
        return (father: couple.husband.name, mother: couple.wife.name)
    }
    
    // MARK: - Identifiable
    
    var id: String { familyId }
    
    // MARK: - Sample Data
    
    /// Sample family for testing
    static func sampleFamily() -> Family {
        let husband = Person(
            name: "Jaakko",
            patronymic: "Jaakonp.",
            birthDate: "09.10.1726",
            deathDate: "07.03.1789",
            asChild: "HYYPPÄ 5",
            noteMarkers: []
        )
        
        let wife = Person(
            name: "Maria",
            patronymic: "Jaakont.",
            birthDate: "02.03.1733",
            deathDate: "18.04.1753",
            asChild: "PIETILÄ 7",
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
        
        let couple = Couple(
            husband: husband,
            wife: wife,
            marriageDate: "08.10.1752",
            children: [child1, child2],
            childrenDiedInfancy: nil,
            coupleNotes: []
        )
        
        return Family(
            familyId: "HYYPPÄ 6",
            pageReferences: ["370"],
            couples: [couple],
            notes: ["Maria kuoli 1784 ja lapsi samana vuonna."],
            noteDefinitions: [:]
        )
    }
    
    /// Complex sample family with multiple couples for cross-reference testing
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
        
        logInfo(.citation, "🔍 FINDING SPOUSE for '\(personName)' in family \(self.familyId)")
        logInfo(.citation, "🔍 Looking for lowercase: '\(lowercaseName)'")
        logInfo(.citation, "🔍 Family has \(self.couples.count) couples")
        
        for (coupleIndex, couple) in self.couples.enumerated() {
            logInfo(.citation, "  Couple \(coupleIndex + 1): \(couple.husband.name) & \(couple.wife.name)")
            logInfo(.citation, "    Husband lowercase: '\(couple.husband.name.lowercased())'")
            logInfo(.citation, "    Wife lowercase: '\(couple.wife.name.lowercased())'")
            
            if couple.husband.name.lowercased() == lowercaseName {
                logInfo(.citation, "✅ FOUND SPOUSE: \(couple.wife.displayName) (wife of \(personName))")
                return couple.wife
            } else if couple.wife.name.lowercased() == lowercaseName {
                logInfo(.citation, "✅ FOUND SPOUSE: \(couple.husband.displayName) (husband of \(personName))")
                return couple.husband
            }
        }
        
        logWarn(.citation, "❌ NO SPOUSE FOUND for '\(personName)' in family \(self.familyId)")
        return nil
    }
}
