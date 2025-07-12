//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

// MARK: - Complete JuuretApp with Enhanced Mock Data (Core/JuuretApp.swift)

import SwiftUI
import FoundationModels

@MainActor
@Observable
class JuuretApp {
    private var session: LanguageModelSession?
    
    var currentFamily: Family?
    var isProcessing = false
    var errorMessage: String?
    
    // Store additional family data for citations
    private var mockFamilyDatabase: [String: Family] = [:]
    
    init() {
        let systemModel = SystemLanguageModel.default
        if systemModel.availability == .available {
            self.session = LanguageModelSession()
        }
        
        // Initialize enhanced mock family database
        createEnhancedMockFamilyDatabase()
    }
    
    func extractFamily(familyId: String) async throws {
        print("🔍 Starting extraction for family ID: \(familyId)")
        
        guard FamilyIDs.validFamilyIds.contains(familyId.uppercased()) else {
            print("❌ Invalid family ID: \(familyId)")
            throw JuuretError.invalidFamilyId(familyId)
        }
        
        print("✅ Family ID validated")
        
        isProcessing = true
        errorMessage = nil
        
        defer {
            isProcessing = false
            print("🏁 Extraction process completed")
        }
        
        print("📝 Creating enhanced mock family data...")
        
        // Simulate processing time
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        let mockFamily = createEnhancedMockFamily(familyId: familyId)
        print("✅ Enhanced mock family created: \(mockFamily.familyId)")
        print("👨‍👩‍👧‍👦 Family has \(mockFamily.children.count) children")
        
        currentFamily = mockFamily
        print("✅ currentFamily updated in JuuretApp")
    }
    
    func generateCitation(for person: Person, in family: Family) -> String {
        print("📄 Generating citation for: \(person.displayName)")
        
        // Check if this is a parent's as_child citation
        if let asChildRef = person.asChildReference,
           let asChildFamily = mockFamilyDatabase[asChildRef] {
            return CitationGenerator.generateAsChildCitation(for: person, in: asChildFamily)
        }
        
        // Check if this is a spouse's as_child citation
        if let spouseFamily = findSpouseAsChildFamily(for: person) {
            return CitationGenerator.generateAsChildCitation(for: person, in: spouseFamily)
        }
        
        // Default to main family citation
        return CitationGenerator.generateMainFamilyCitation(family: family)
    }
    
    func generateSpouseCitation(spouseName: String, in family: Family) -> String {
        print("💑 Generating spouse citation for: \(spouseName)")
        
        // Handle "Elias Iso-Peitso" specifically
        let searchName = spouseName.replacingOccurrences(of: " Iso-Peitso", with: "")
        
        // Search for the spouse in our mock database
        for (_, mockFamily) in mockFamilyDatabase {
            // Check if this person is a child in this family
            if let spouse = mockFamily.children.first(where: { person in
                return person.name.lowercased() == searchName.lowercased() ||
                       person.displayName.lowercased() == spouseName.lowercased()
            }) {
                return CitationGenerator.generateAsChildCitation(for: spouse, in: mockFamily)
            }
            
            // Also check if they're a parent who became a child elsewhere
            if mockFamily.father.name.lowercased() == searchName.lowercased() ||
               mockFamily.father.displayName.lowercased() == spouseName.lowercased() {
                if let asChildRef = mockFamily.father.asChildReference,
                   let asChildFamily = mockFamilyDatabase[asChildRef] {
                    return CitationGenerator.generateAsChildCitation(for: mockFamily.father, in: asChildFamily)
                }
            }
        }
        
        return "Citation for \(spouseName) not found in available records. Additional research needed in parish records."
    }
    
    func generateHiskiQuery(for date: String, eventType: EventType) -> String {
        print("🔍 Generating Hiski query for: \(date) (\(eventType))")
        return "https://hiski.genealogia.fi/hiski?en+mock_query_\(eventType)_\(date.replacingOccurrences(of: " ", with: "_"))"
    }
    
    private func findSpouseAsChildFamily(for person: Person) -> Family? {
        // Look for this person as a child in any family
        for (_, family) in mockFamilyDatabase {
            if family.children.contains(where: { $0.name == person.name }) {
                return family
            }
        }
        return nil
    }
    
    private func createEnhancedMockFamilyDatabase() {
        // Create connected families for realistic citations
        
        // KORPI 5 - Matti's as_child family (WITH SIBLINGS)
        let korpi5 = Family(
            familyId: "KORPI 5",
            pageReferences: ["103", "104"],
            father: Person(
                name: "Erik",
                patronymic: "Matinp.",
                birthDate: "12 August 1685",
                deathDate: "15 March 1755",
                marriageDate: "20 November 1720",
                spouse: "Maija Juhont.",
                asChildReference: nil,
                asParentReference: nil,
                familySearchId: "ABC1-234",
                noteMarkers: []
            ),
            mother: Person(
                name: "Maija",
                patronymic: "Juhont.",
                birthDate: "8 October 1695",
                deathDate: "2 January 1760",
                marriageDate: "20 November 1720",
                spouse: "Erik Matinp.",
                asChildReference: nil,
                asParentReference: nil,
                familySearchId: "DEF5-678",
                noteMarkers: []
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Anna",
                    patronymic: nil,
                    birthDate: "15 June 1725",
                    deathDate: "10 September 1790",
                    marriageDate: "12 October 1748",
                    spouse: "Juho Videnoja",
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "GHI9-012",
                    noteMarkers: []
                ),
                Person(
                    name: "Matti",
                    patronymic: "Erikinp.",
                    birthDate: "9 September 1727",
                    deathDate: "22 August 1812",
                    marriageDate: "14 October 1750",
                    spouse: "Brita Matint.",
                    asChildReference: nil,
                    asParentReference: "KORPI 6",
                    familySearchId: "LCJZ-BH3",
                    noteMarkers: []
                ),
                Person(
                    name: "Liisa",
                    patronymic: nil,
                    birthDate: "3 March 1730",
                    deathDate: nil,
                    marriageDate: nil,
                    spouse: nil,
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "JKL3-789",
                    noteMarkers: []
                )
            ],
            notes: ["Talo perustettu 1720.", "Lapsena kuollut 2."],
            childrenDiedInfancy: 2
        )
        
        // SIKALA 5 - Brita's as_child family (WITH SIBLINGS)
        let sikala5 = Family(
            familyId: "SIKALA 5",
            pageReferences: ["220", "221"],
            father: Person(
                name: "Matti",
                patronymic: "Antinp.",
                birthDate: "3 April 1700",
                deathDate: "18 November 1775",
                marriageDate: "25 June 1728",
                spouse: "Liisa Pietarint.",
                asChildReference: nil,
                asParentReference: nil,
                familySearchId: "JKL3-456",
                noteMarkers: []
            ),
            mother: Person(
                name: "Liisa",
                patronymic: "Pietarint.",
                birthDate: "12 December 1708",
                deathDate: "5 July 1780",
                marriageDate: "25 June 1728",
                spouse: "Matti Antinp.",
                asChildReference: nil,
                asParentReference: nil,
                familySearchId: "MNO7-890",
                noteMarkers: []
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Juho",
                    patronymic: nil,
                    birthDate: "22 March 1730",
                    deathDate: "8 December 1795",
                    marriageDate: "15 September 1755",
                    spouse: "Anna Koski",
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "PQR1-234",
                    noteMarkers: []
                ),
                Person(
                    name: "Brita",
                    patronymic: "Matint.",
                    birthDate: "5 September 1731",
                    deathDate: "11 July 1769",
                    marriageDate: "14 October 1750",
                    spouse: "Matti Erikinp.",
                    asChildReference: nil,
                    asParentReference: "KORPI 6",
                    familySearchId: "KCJW-98X",
                    noteMarkers: []
                ),
                Person(
                    name: "Katariina",
                    patronymic: nil,
                    birthDate: "10 August 1733",
                    deathDate: nil,
                    marriageDate: nil,
                    spouse: nil,
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "STU5-678",
                    noteMarkers: []
                )
            ],
            notes: ["Talo sijaitsee Hanhisalossa.", "Lapsena kuollut 1."],
            childrenDiedInfancy: 1
        )
        
        // ISO-PEITSO III 2 - Maria's as_parent family (for death date and marriage details)
        let isoPeitsoIII2 = Family(
            familyId: "ISO-PEITSO III 2",
            pageReferences: ["480", "481"],
            father: Person(
                name: "Elias",
                patronymic: "Juhonp.",
                birthDate: "15 March 1748",
                deathDate: "8 December 1820",
                marriageDate: "6 November 1773",
                spouse: "Maria",
                asChildReference: "ISO-PEITSO III 1",
                asParentReference: nil,
                familySearchId: "GMG6-NCZ",
                noteMarkers: []
            ),
            mother: Person(
                name: "Maria",
                patronymic: nil,
                birthDate: "10 February 1752",
                deathDate: "22 January 1777", // Added death date as requested
                marriageDate: "6 November 1773",
                spouse: "Elias Juhonp.",
                asChildReference: "KORPI 6",
                asParentReference: nil,
                familySearchId: "KJJH-2R9",
                noteMarkers: []
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Juho",
                    patronymic: nil,
                    birthDate: "20 September 1774",
                    deathDate: nil,
                    marriageDate: nil,
                    spouse: nil,
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "STU5-678",
                    noteMarkers: []
                ),
                Person(
                    name: "Anna",
                    patronymic: nil,
                    birthDate: "8 May 1776",
                    deathDate: nil,
                    marriageDate: nil,
                    spouse: nil,
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "VWX9-012",
                    noteMarkers: []
                )
            ],
            notes: ["Maria kuoli synnytyksen jälkeen."],
            childrenDiedInfancy: 0
        )
        
        // ISO-PEITSO III 1 - Elias's as_child family (FIXED for spouse search)
        let isoPeitsoIII1 = Family(
            familyId: "ISO-PEITSO III 1",
            pageReferences: ["478", "479"],
            father: Person(
                name: "Juho",
                patronymic: "Matinp.",
                birthDate: "20 January 1720",
                deathDate: "3 August 1785",
                marriageDate: "15 October 1745",
                spouse: "Katariina Antint.",
                asChildReference: nil,
                asParentReference: nil,
                familySearchId: "YZA3-456",
                noteMarkers: []
            ),
            mother: Person(
                name: "Katariina",
                patronymic: "Antint.",
                birthDate: "8 July 1725",
                deathDate: "12 February 1790",
                marriageDate: "15 October 1745",
                spouse: "Juho Matinp.",
                asChildReference: nil,
                asParentReference: nil,
                familySearchId: "BCD7-890",
                noteMarkers: []
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Matti",
                    patronymic: nil,
                    birthDate: "12 September 1746",
                    deathDate: nil,
                    marriageDate: nil,
                    spouse: nil,
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "EFG1-234",
                    noteMarkers: []
                ),
                Person(
                    name: "Elias", // This will match the spouse search for "Elias Iso-Peitso"
                    patronymic: "Juhonp.",
                    birthDate: "15 March 1748",
                    deathDate: "8 December 1820",
                    marriageDate: "6 November 1773",
                    spouse: "Maria",
                    asChildReference: nil,
                    asParentReference: "ISO-PEITSO III 2",
                    familySearchId: "GMG6-NCZ",
                    noteMarkers: []
                ),
                Person(
                    name: "Anna",
                    patronymic: nil,
                    birthDate: "5 July 1750",
                    deathDate: nil,
                    marriageDate: nil,
                    spouse: nil,
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "HIJ5-678",
                    noteMarkers: []
                )
            ],
            notes: ["Iso-Peitso talo perustettu 1740.", "Lapsena kuollut 1."],
            childrenDiedInfancy: 1
        )
        
        // Store in database
        mockFamilyDatabase["KORPI 5"] = korpi5
        mockFamilyDatabase["SIKALA 5"] = sikala5
        mockFamilyDatabase["ISO-PEITSO III 2"] = isoPeitsoIII2
        mockFamilyDatabase["ISO-PEITSO III 1"] = isoPeitsoIII1
    }
    
    private func createEnhancedMockFamily(familyId: String) -> Family {
        return Family(
            familyId: familyId.uppercased(),
            pageReferences: ["105", "106"],
            father: Person(
                name: "Matti",
                patronymic: "Erikinp.",
                birthDate: "9 September 1727",
                deathDate: "22 August 1812",
                marriageDate: "14 October 1750",
                spouse: "Brita Matint.",
                asChildReference: "KORPI 5", // Now has as_child family with siblings
                asParentReference: nil,
                familySearchId: "LCJZ-BH3",
                noteMarkers: []
            ),
            mother: Person(
                name: "Brita",
                patronymic: "Matint.",
                birthDate: "5 September 1731",
                deathDate: "11 July 1769",
                marriageDate: "14 October 1750",
                spouse: "Matti Erikinp.",
                asChildReference: "SIKALA 5", // Now has as_child family with siblings
                asParentReference: nil,
                familySearchId: "KCJW-98X",
                noteMarkers: []
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Maria",
                    patronymic: nil,
                    birthDate: "10 February 1752",
                    deathDate: "22 January 1777", // Added death date
                    marriageDate: "6 November 1773", // Complete date from as_parent family
                    spouse: "Elias Iso-Peitso", // This will now find as_child citation
                    asChildReference: nil,
                    asParentReference: "ISO-PEITSO III 2",
                    familySearchId: "KJJH-2R9",
                    noteMarkers: []
                ),
                Person(
                    name: "Kaarin",
                    patronymic: nil,
                    birthDate: "1 February 1753",
                    deathDate: "17 April 1795",
                    marriageDate: nil,
                    spouse: nil,
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "LJKQ-PLT",
                    noteMarkers: []
                ),
                Person(
                    name: "Erik",
                    patronymic: nil,
                    birthDate: "20 July 1756",
                    deathDate: nil,
                    marriageDate: nil,
                    spouse: nil,
                    asChildReference: nil,
                    asParentReference: nil,
                    familySearchId: "GMVS-VB1",
                    noteMarkers: []
                )
            ],
            notes: ["Lapsena kuollut 4."],
            childrenDiedInfancy: 4
        )
    }
}
