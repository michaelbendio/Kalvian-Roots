//
//  Family.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation
import FoundationModels

/**
 * Family.swift - Core genealogical data structures
 *
 * Contains Family struct for Finnish genealogy data from Juuret Kälviällä.
 * Phase 2: Using Foundation Models @Generable for structured extraction!
 */

/**
 * Complete family unit from Juuret Kälviällä genealogical text.
 *
 * Foundation Models @Generable: Enables session.respond(to:, generating: Family.self)
 * for direct struct generation from Finnish genealogical text.
 */
@Generable
struct Family: Hashable, Sendable {
    @Guide(description: "Family ID like 'KORPI 6' or 'ISO-PEITSO II 3'")
    var familyId: String
    
    @Guide(description: "Source page numbers like ['105', '106']")
    var pageReferences: [String]
    
    @Guide(description: "Father with vital dates and genealogical info")
    var father: Person
    
    @Guide(description: "Mother with vital dates, may be nil")
    var mother: Person?
    
    @Guide(description: "Additional spouses (II puoliso, III puoliso)")
    var additionalSpouses: [Person]
    
    @Guide(description: "All children with birth dates and marriage info")
    var children: [Person]
    
    @Guide(description: "Historical notes about migrations, occupations")
    var notes: [String]
    
    @Guide(description: "Number from 'Lapsena kuollut N' notation")
    var childrenDiedInfancy: Int?
    
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
    
    /// Children with spouse info for cross-reference resolution
    var marriedChildren: [Person] {
        children.filter { $0.spouse != nil }
    }
    
    // MARK: - Methods
    
    /// Parent names for Hiski birth queries
    func getParentNames(for child: Person) -> (father: String, mother: String?) {
        return (father.displayName, mother?.displayName)
    }
    
    /// Validate family structure for genealogical accuracy
    func validateStructure() -> [String] {
        var warnings: [String] = []
        
        if father.name.isEmpty {
            warnings.append("Father name is required")
        }
        
        for person in allPersons {
            if let asChildRef = person.asChildReference {
                if !FamilyIDs.validFamilyIds.contains(asChildRef.uppercased()) {
                    warnings.append("Invalid as_child reference: \(asChildRef) for \(person.name)")
                }
            }
        }
        
        return warnings
    }
    
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
        
        return Family(
            familyId: "KORPI 6",
            pageReferences: ["105", "106"],
            father: father,
            mother: mother,
            additionalSpouses: [],
            children: [child1],
            notes: ["Lapsena kuollut 4."],
            childrenDiedInfancy: 4
        )
    }
}
