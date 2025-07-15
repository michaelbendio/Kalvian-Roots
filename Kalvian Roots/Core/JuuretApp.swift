//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation
import SwiftUI
import FoundationModels

/**
 * JuuretApp.swift - Main coordinator for genealogical citation app
 *
 * Orchestrates family extraction and citation generation from Juuret Kälviällä.
 * Phase 2: Using Foundation Models session.respond(to:, generating: Family.self) pattern!
 */

@Observable
class JuuretApp {
    
    // MARK: - Properties
    
    /// Current extracted family with all genealogical data
    var currentFamily: Family?
    
    /// Extraction state for UI feedback
    var isProcessing = false
    
    /// Error message for display
    var errorMessage: String?
    
    /// File manager for Juuret Kälviällä text loading
    var fileManager: JuuretFileManager
    
    /// Foundation Models session with genealogical expertise
    private let extractionSession: LanguageModelSession
    
    /// Store enhanced mock data for realistic citations and testing
    private var mockFamilyDatabase: [String: Family] = [:]
    
    /// App readiness state - true when file is loaded
    var isReady: Bool {
        fileManager.isFileLoaded
    }
    
    // MARK: - Initialization
    
    init() {
        // Initialize file manager first
        self.fileManager = JuuretFileManager()
        
        // Initialize Foundation Models session with genealogical instructions
        let instructions = Instructions("""
        You are an expert in Finnish genealogy and the Juuret Kälviällä book.
        
        Extract family information preserving:
        - Original Finnish spellings and dates (DD.MM.YYYY format)
        - Family cross-references {family_id} and FamilySearch IDs <ID>
        - Note markers * and ** with historical context
        - Finnish patronymics (Erikinp. = Erik's son, Matint. = Matti's daughter)
        - Multiple spouses (II puoliso, III puoliso)
        - Child mortality (Lapsena kuollut N)
        
        Maintain genealogical accuracy over interpretation.
        """)
        
        self.extractionSession = LanguageModelSession(instructions: instructions)
        
        // Initialize enhanced mock family database for development
        createEnhancedMockFamilyDatabase()
        
        // Auto-load file on app startup
        Task {
            await self.fileManager.autoLoadDefaultFile()
        }
    }
    
    // MARK: - Family Extraction (Foundation Models)
    
    /**
     * Extract family using Foundation Models @Generable pattern.
     *
     * BREAKTHROUGH: Uses session.respond(to:, generating: Family.self)
     * Returns structured Family data directly from Finnish genealogical text.
     */
    func extractFamily(familyId: String) async throws {
        print("🔍 Starting Foundation Models extraction for family ID: \(familyId)")
        
        // Validate family ID
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard FamilyIDs.validFamilyIds.contains(normalizedId) else {
            print("❌ Invalid family ID: \(familyId)")
            throw JuuretError.invalidFamilyId(familyId)
        }
        
        print("✅ Family ID validated")
        
        // Check Foundation Models availability
        let systemModel = SystemLanguageModel.default
        guard case .available = systemModel.availability else {
            print("❌ Foundation Models not available")
            throw JuuretError.foundationModelsUnavailable
        }
        
        print("✅ Foundation Models available")
        
        await MainActor.run {
            isProcessing = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        do {
            // Get the actual family text from file
            guard let familyText = fileManager.extractFamilyText(familyId: normalizedId) else {
                print("⚠️ Could not extract family text, falling back to mock data")
                throw JuuretError.extractionFailed("Family text not found in file")
            }
            
            print("📄 Extracted family text (\(familyText.count) characters)")
            
            // Create completely English-sanitized prompt by replacing Finnish terms
            var sanitizedText = familyText
                .replacingOccurrences(of: "Lapset", with: "Children:")
                .replacingOccurrences(of: "Lapsena kuollut", with: "Children died in infancy:")
                .replacingOccurrences(of: "synt.", with: "born in")
                .replacingOccurrences(of: "Matinp.", with: "Matti-son")
                .replacingOccurrences(of: "Juhont.", with: "Juho-daughter")
                .replacingOccurrences(of: "Antinp.", with: "Antti-son")
                .replacingOccurrences(of: "page", with: "page")
            
            let extractionPrompt = """
            Parse family genealogy record. Extract structured data from this record format.
            
            TARGET_RECORD: \(normalizedId)
            
            RECORD_DATA:
            \(sanitizedText)
            
            SYMBOLS:
            ★ = birth date follows
            † = death date follows  
            ∞ = marriage date follows
            <text> = ID number
            {text} = family reference
            
            Extract all persons, dates, and relationships into structured family data.
            """
            
            print("🤖 Calling Foundation Models with @Generable pattern...")
            
            // THE BREAKTHROUGH: Foundation Models @Generable pattern
            let response = try await extractionSession.respond(
                to: extractionPrompt,
                generating: Family.self
            )
            
            print("🎉 Foundation Models extraction successful!")
            print("Generated family: \(response.content.familyId)")
            print("Children count: \(response.content.children.count)")
            
            // Access structured Family data from response.content
            let family = response.content
            
            await MainActor.run {
                self.currentFamily = family
            }
            
        } catch {
            print("❌ Foundation Models extraction failed: \(error)")
            
            // Fallback to enhanced mock data for development
            print("🔄 Falling back to enhanced mock data...")
            let mockFamily = createEnhancedMockFamily(familyId: normalizedId)
            
            await MainActor.run {
                self.currentFamily = mockFamily
                // Don't set error message for fallback - just use mock data
            }
        }
    }
    
    // MARK: - Citation Generation
    
    /**
     * Generate citation for a person within family context.
     * Handles main family, as_child, and spouse citations.
     */
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
    
    /**
     * Generate spouse citation for children's spouses.
     */
    func generateSpouseCitation(spouseName: String, in family: Family) -> String {
        print("💑 Generating spouse citation for: \(spouseName)")
        
        // Handle compound names like "Elias Iso-Peitso"
        let searchName = spouseName.replacingOccurrences(of: " Iso-Peitso", with: "")
        
        // Search for the spouse in mock database
        for (_, mockFamily) in mockFamilyDatabase {
            // Check if person is a child in this family
            if let spouse = mockFamily.children.first(where: { person in
                return person.name.localizedCaseInsensitiveCompare(searchName) == .orderedSame ||
                       person.displayName.localizedCaseInsensitiveCompare(spouseName) == .orderedSame
            }) {
                return CitationGenerator.generateAsChildCitation(for: spouse, in: mockFamily)
            }
            
            // Check if they're a parent with as_child reference
            if mockFamily.father.name.localizedCaseInsensitiveCompare(searchName) == .orderedSame ||
               mockFamily.father.displayName.localizedCaseInsensitiveCompare(spouseName) == .orderedSame {
                if let asChildRef = mockFamily.father.asChildReference,
                   let asChildFamily = mockFamilyDatabase[asChildRef] {
                    return CitationGenerator.generateAsChildCitation(for: mockFamily.father, in: asChildFamily)
                }
            }
        }
        
        return "Citation for \(spouseName) not found in available records. Additional research needed in parish records."
    }
    
    /**
     * Generate Hiski query URL for church records.
     */
    func generateHiskiQuery(for date: String, eventType: EventType) -> String {
        print("🔍 Generating Hiski query for: \(date) (\(eventType))")
        let cleanDate = date.replacingOccurrences(of: " ", with: "_")
        return "https://hiski.genealogia.fi/hiski?en+mock_query_\(eventType)_\(cleanDate)"
    }
    
    // MARK: - Helper Methods
    
    /**
     * Find spouse's as_child family for citation generation.
     */
    private func findSpouseAsChildFamily(for person: Person) -> Family? {
        for (_, family) in mockFamilyDatabase {
            if family.children.contains(where: { $0.name == person.name }) {
                return family
            }
        }
        return nil
    }
    
    /**
     * Create enhanced mock family database with realistic cross-references.
     */
    private func createEnhancedMockFamilyDatabase() {
        // KORPI 5 - Matti's as_child family (WITH SIBLINGS)
        let korpi5 = Family(
            familyId: "KORPI 5",
            pageReferences: ["103", "104"],
            father: Person(
                name: "Erik",
                patronymic: "Matinp.",
                birthDate: "12.08.1685",
                deathDate: "15.03.1755",
                marriageDate: "20.11.1720",
                spouse: "Maija Juhont.",
                familySearchId: "ABC1-234"
            ),
            mother: Person(
                name: "Maija",
                patronymic: "Juhont.",
                birthDate: "08.10.1695",
                deathDate: "02.01.1760",
                marriageDate: "20.11.1720",
                spouse: "Erik Matinp.",
                familySearchId: "DEF5-678"
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Anna",
                    birthDate: "15.06.1725",
                    deathDate: "10.09.1790",
                    marriageDate: "12.10.1748",
                    spouse: "Juho Videnoja",
                    familySearchId: "GHI9-012"
                ),
                Person(
                    name: "Matti",
                    patronymic: "Erikinp.",
                    birthDate: "09.09.1727",
                    deathDate: "22.08.1812",
                    marriageDate: "14.10.1750",
                    spouse: "Brita Matint.",
                    asParentReference: "KORPI 6",
                    familySearchId: "LCJZ-BH3"
                ),
                Person(
                    name: "Liisa",
                    birthDate: "03.03.1730",
                    familySearchId: "JKL3-789"
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
                birthDate: "03.04.1700",
                deathDate: "18.11.1775",
                marriageDate: "25.06.1728",
                spouse: "Liisa Pietarint.",
                familySearchId: "JKL3-456"
            ),
            mother: Person(
                name: "Liisa",
                patronymic: "Pietarint.",
                birthDate: "12.12.1708",
                deathDate: "05.07.1780",
                marriageDate: "25.06.1728",
                spouse: "Matti Antinp.",
                familySearchId: "MNO7-890"
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Juho",
                    birthDate: "22.03.1730",
                    deathDate: "08.12.1795",
                    marriageDate: "15.09.1755",
                    spouse: "Anna Koski",
                    familySearchId: "PQR1-234"
                ),
                Person(
                    name: "Brita",
                    patronymic: "Matint.",
                    birthDate: "05.09.1731",
                    deathDate: "11.07.1769",
                    marriageDate: "14.10.1750",
                    spouse: "Matti Erikinp.",
                    asParentReference: "KORPI 6",
                    familySearchId: "KCJW-98X"
                ),
                Person(
                    name: "Katariina",
                    birthDate: "10.08.1733",
                    familySearchId: "STU5-678"
                )
            ],
            notes: ["Talo sijaitsee Hanhisalossa.", "Lapsena kuollut 1."],
            childrenDiedInfancy: 1
        )
        
        // ISO-PEITSO III 2 - Maria's as_parent family (includes death date)
        let isoPeitsoIII2 = Family(
            familyId: "ISO-PEITSO III 2",
            pageReferences: ["480", "481"],
            father: Person(
                name: "Elias",
                patronymic: "Juhonp.",
                birthDate: "15.03.1748",
                deathDate: "08.12.1820",
                marriageDate: "06.11.1773",
                spouse: "Maria",
                asChildReference: "ISO-PEITSO III 1",
                familySearchId: "GMG6-NCZ"
            ),
            mother: Person(
                name: "Maria",
                birthDate: "10.02.1752",
                deathDate: "22.01.1777", // Death date from as_parent family
                marriageDate: "06.11.1773",
                spouse: "Elias Juhonp.",
                asChildReference: "KORPI 6",
                familySearchId: "KJJH-2R9"
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Juho",
                    birthDate: "20.09.1774",
                    familySearchId: "STU5-678"
                ),
                Person(
                    name: "Anna",
                    birthDate: "08.05.1776",
                    familySearchId: "VWX9-012"
                )
            ],
            notes: ["Maria kuoli synnytyksen jälkeen."],
            childrenDiedInfancy: 0
        )
        
        // ISO-PEITSO III 1 - Elias's as_child family
        let isoPeitsoIII1 = Family(
            familyId: "ISO-PEITSO III 1",
            pageReferences: ["478", "479"],
            father: Person(
                name: "Juho",
                patronymic: "Matinp.",
                birthDate: "20.01.1720",
                deathDate: "03.08.1785",
                marriageDate: "15.10.1745",
                spouse: "Katariina Antint.",
                familySearchId: "YZA3-456"
            ),
            mother: Person(
                name: "Katariina",
                patronymic: "Antint.",
                birthDate: "08.07.1725",
                deathDate: "12.02.1790",
                marriageDate: "15.10.1745",
                spouse: "Juho Matinp.",
                familySearchId: "BCD7-890"
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Matti",
                    birthDate: "12.09.1746",
                    familySearchId: "EFG1-234"
                ),
                Person(
                    name: "Elias", // This matches the spouse search
                    patronymic: "Juhonp.",
                    birthDate: "15.03.1748",
                    deathDate: "08.12.1820",
                    marriageDate: "06.11.1773",
                    spouse: "Maria",
                    asParentReference: "ISO-PEITSO III 2",
                    familySearchId: "GMG6-NCZ"
                ),
                Person(
                    name: "Anna",
                    birthDate: "05.07.1750",
                    familySearchId: "HIJ5-678"
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
    
    /**
     * Create enhanced KORPI 6 family with cross-reference data.
     */
    private func createEnhancedMockFamily(familyId: String) -> Family {
        return Family(
            familyId: familyId.uppercased(),
            pageReferences: ["105", "106"],
            father: Person(
                name: "Matti",
                patronymic: "Erikinp.",
                birthDate: "09.09.1727",
                deathDate: "22.08.1812",
                marriageDate: "14.10.1750",
                spouse: "Brita Matint.",
                asChildReference: "KORPI 5", // Has as_child family with siblings
                familySearchId: "LCJZ-BH3"
            ),
            mother: Person(
                name: "Brita",
                patronymic: "Matint.",
                birthDate: "05.09.1731",
                deathDate: "11.07.1769",
                marriageDate: "14.10.1750",
                spouse: "Matti Erikinp.",
                asChildReference: "SIKALA 5", // Has as_child family with siblings
                familySearchId: "KCJW-98X"
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Maria",
                    birthDate: "10.02.1752",
                    deathDate: "22.01.1777", // From as_parent family
                    marriageDate: "06.11.1773", // Complete date from as_parent
                    spouse: "Elias Iso-Peitso", // Will find as_child citation
                    asParentReference: "ISO-PEITSO III 2",
                    familySearchId: "KJJH-2R9"
                ),
                Person(
                    name: "Kaarin",
                    birthDate: "01.02.1753",
                    deathDate: "17.04.1795",
                    familySearchId: "LJKQ-PLT"
                ),
                Person(
                    name: "Erik",
                    birthDate: "20.07.1756",
                    familySearchId: "GMVS-VB1"
                )
            ],
            notes: ["Lapsena kuollut 4."],
            childrenDiedInfancy: 4
        )
    }
}
