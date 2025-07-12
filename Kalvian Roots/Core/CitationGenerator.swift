//
//  CitationGenerator.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//


import Foundation

struct CitationGenerator {
    static func generateMainFamilyCitation(family: Family) -> String {
        var citation = "Information on pages \(family.pageReferences.joined(separator: ", ")) includes:\n\n"
        
        // Parents information
        citation += "\(family.father.displayName), b \(family.father.birthDate ?? "unknown")"
        if let deathDate = family.father.deathDate {
            citation += ", d \(deathDate)"
        }
        citation += "\n"
        
        if let mother = family.mother {
            citation += "\(mother.displayName), b \(mother.birthDate ?? "unknown")"
            if let marriageDate = mother.marriageDate {
                citation += ", m \(marriageDate)"
            }
            if let deathDate = mother.deathDate {
                citation += ", d \(deathDate)"
            }
            citation += "\n"
        }
        
        // Children
        if !family.children.isEmpty {
            citation += "\nChildren:\n"
            for child in family.children {
                citation += "\(child.name), b \(child.birthDate ?? "unknown")"
                if let marriageDate = child.marriageDate, let spouse = child.spouse {
                    citation += ", m \(spouse) \(marriageDate)"
                }
                if let deathDate = child.deathDate {
                    citation += ", d \(deathDate)"
                }
                citation += "\n"
            }
        }
        
        // Notes
        if !family.notes.isEmpty {
            citation += "\nNotes:\n"
            for note in family.notes {
                citation += "• \(note)\n"
            }
        }
        
        return citation
    }
    
    static func generateAsChildCitation(for person: Person, in family: Family) -> String {
        var citation = "Information on pages \(family.pageReferences.joined(separator: ", ")) includes:\n\n"
        
        citation += "\(family.father.displayName), b \(family.father.birthDate ?? "unknown")"
        if let deathDate = family.father.deathDate {
            citation += ", d \(deathDate)"
        }
        citation += "\n"
        
        if let mother = family.mother {
            citation += "\(mother.displayName), b \(mother.birthDate ?? "unknown")"
            if let marriageDate = mother.marriageDate {
                citation += ", m \(marriageDate)"
            }
            if let deathDate = mother.deathDate {
                citation += ", d \(deathDate)"
            }
            citation += "\n"
        }
        
        citation += "\nChildren:\n"
        for child in family.children {
            let prefix = child.name == person.name ? "→ " : "  "
            citation += "\(prefix)\(child.name), b \(child.birthDate ?? "unknown")"
            if let marriageDate = child.marriageDate, let spouse = child.spouse {
                citation += ", m \(spouse) \(marriageDate)"
            }
            if let deathDate = child.deathDate {
                citation += ", d \(deathDate)"
            }
            citation += "\n"
        }
        
        if !family.notes.isEmpty {
            citation += "\nNotes:\n"
            for note in family.notes {
                citation += "• \(note)\n"
            }
        }
        
        return citation
    }
}
