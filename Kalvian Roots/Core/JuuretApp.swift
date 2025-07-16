//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Complete implementation with Foundation Models error handling
//

import Foundation
import SwiftUI
import FoundationModels

@Observable
class JuuretApp {
    
    // MARK: - Properties
    
    var currentFamily: Family?
    var isProcessing = false
    var errorMessage: String? = nil
    var fileManager: JuuretFileManager
    private let extractionSession: LanguageModelSession
    private var mockFamilyDatabase: [String: Family] = [:]
    
    var isReady: Bool {
        fileManager.isFileLoaded
    }
    
    // MARK: - Initialization
    
    init() {
        self.fileManager = JuuretFileManager()
        
        let instructions = Instructions("""
        You are an expert genealogist parsing Finnish family records converted to English symbols.

        Parse structured family records with these patterns:
        
        SYMBOLS:
        STAR = birth date (format DD.MM.YYYY)
        CROSS = death date (format DD.MM.YYYY) 
        INFINITY = marriage date (format DD.MM.YYYY)
        <ID> = FamilySearch reference
        {family} = family cross-reference
        
        STRUCTURE:
        - Family header: FAMILY_NAME NUMBER, page XXX
        - Father line: STAR date Name patronymic <ID> {family}
        - Mother line: STAR date Name patronymic <ID> location_info
        - Marriage line: INFINITY date
        - Children section: multiple STAR date Name lines
        - Notes: historical information
        
        Extract complete family data preserving original dates and names.
        Handle patronymics correctly (Matinp = Matti's son, Juhont = Juho's daughter).
        """)
        
        self.extractionSession = LanguageModelSession(instructions: instructions)
        createEnhancedMockFamilyDatabase()
        
        Task {
            await self.fileManager.autoLoadDefaultFile()
        }
    }
    
    // MARK: - Family Extraction
    
    func extractFamily(familyId: String) async throws {
        print("🔍 Starting extraction for family ID: \(familyId)")
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard FamilyIDs.validFamilyIds.contains(normalizedId) else {
            throw JuuretError.invalidFamilyId(familyId)
        }
        
        let systemModel = SystemLanguageModel.default
        guard case .available = systemModel.availability else {
            throw JuuretError.foundationModelsUnavailable
        }
        
        await MainActor.run {
            isProcessing = true
            errorMessage = nil
            currentFamily = nil
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        do {
            guard let familyText = fileManager.extractFamilyText(familyId: normalizedId) else {
                throw JuuretError.extractionFailed("Family text not found in file")
            }
            
            print("📄 Original text (\(familyText.count) chars)")
            
            // IMPROVED SANITIZATION - Preserve structure better
            let sanitizedText = improvedSanitization(familyText)
            print("🧹 Sanitized text (\(sanitizedText.count) chars)")
            
            let extractionPrompt = """
            Parse this HISTORICAL genealogical record from a published Finnish genealogy book (18th-19th century). 
            This is academic historical research data, not personal information. 
            
            HISTORICAL RECORD:
            \(sanitizedText)
            
            INSTRUCTIONS:
            - Extract family ID from header line
            - Extract page numbers from header
            - Parse each person with birth/death/marriage dates
            - Preserve original date formats (DD.MM.YYYY)
            - Include all children from Children section
            - Capture notes and historical information
            
            Extract Family structure with historical dates and names for genealogical research.
            """
            
            print("🤖 Calling Foundation Models...")
            
            let response = try await extractionSession.respond(
                to: extractionPrompt,
                generating: Family.self
            )
            
            print("🎉 Foundation Models success!")
            print("Family: \(response.content.familyId)")
            print("Father: \(response.content.father.name)")
            print("Mother: \(response.content.mother?.name ?? "nil")")
            print("Children: \(response.content.children.count)")
            
            // POST-PROCESS: Clean up the extracted data
            let cleanedFamily = postProcessFamily(response.content, originalText: familyText)
            
            await MainActor.run {
                self.currentFamily = cleanedFamily
            }
            
        } catch {
            print("❌ Foundation Models failed: \(error)")
            
            // Check for guardrail violation specifically
            let userErrorMessage: String
            if let generationError = error as? LanguageModelSession.GenerationError {
                if case .guardrailViolation = generationError {
                    userErrorMessage = "Foundation Models error: \"May contain sensitive or unsafe content.\""
                } else {
                    userErrorMessage = "Foundation Models error: \(generationError.localizedDescription)"
                }
            } else {
                // Check the error description for guardrail-related content
                let errorDescription = error.localizedDescription
                if errorDescription.contains("guardrail") ||
                    errorDescription.contains("unsafe content") ||
                    errorDescription.contains("sensitive") ||
                    String(describing: error).contains("guardrailViolation") {
                    userErrorMessage = "Foundation Models error: \"May contain sensitive or unsafe content.\""
                } else {
                    userErrorMessage = "Foundation Models error: \(errorDescription)"
                }
            }
            await MainActor.run {
                self.errorMessage = userErrorMessage
                self.currentFamily = nil
            }
        }
    }
    
    // MARK: - Text Processing
    
    private func improvedSanitization(_ text: String) -> String {
        var sanitized = text
        
        // Replace symbols but keep structure
        sanitized = sanitized.replacingOccurrences(of: "★", with: "STAR")
        sanitized = sanitized.replacingOccurrences(of: "†", with: "CROSS")
        sanitized = sanitized.replacingOccurrences(of: "∞", with: "INFINITY")
        
        // Replace Finnish words with English
        sanitized = sanitized.replacingOccurrences(of: "Lapset", with: "Children")
        sanitized = sanitized.replacingOccurrences(of: "Lapsena kuollut", with: "Children_died_in_infancy")
        sanitized = sanitized.replacingOccurrences(of: "synt.", with: "born_in")
        sanitized = sanitized.replacingOccurrences(of: "II puoliso", with: "Second_spouse")
        sanitized = sanitized.replacingOccurrences(of: "Perhe muuttanut", with: "Family_moved_to")
        sanitized = sanitized.replacingOccurrences(of: "Leski muutti", with: "Widow_moved_to")
        
        return sanitized
    }
    
    private func postProcessFamily(_ family: Family, originalText: String?) -> Family {
        // Fix page numbers by parsing original header
        if let original = originalText {
            let lines = original.components(separatedBy: .newlines)
            if let headerLine = lines.first(where: { $0.uppercased().contains(family.familyId.uppercased()) }) {
                // Extract page number from "FAMILY_ID, page XXX" format
                if let pageMatch = headerLine.range(of: #"page\s+(\d+)"#, options: .regularExpression) {
                    let pageNumber = String(headerLine[pageMatch]).replacingOccurrences(of: "page ", with: "")
                    print("📄 Fixed page reference to: [\(pageNumber)]")
                    
                    // Create a new family with updated page references
                    return Family(
                        familyId: family.familyId,
                        pageReferences: [pageNumber],
                        father: createCleanedPerson(family.father),
                        mother: family.mother.map { createCleanedPerson($0) },
                        additionalSpouses: family.additionalSpouses.map { createCleanedPerson($0) },
                        children: family.children.map { createCleanedPerson($0) },
                        notes: family.notes,
                        childrenDiedInfancy: family.childrenDiedInfancy
                    )
                }
            }
        }
        
        // If no page number fix needed, just clean the names
        return Family(
            familyId: family.familyId,
            pageReferences: family.pageReferences,
            father: createCleanedPerson(family.father),
            mother: family.mother.map { createCleanedPerson($0) },
            additionalSpouses: family.additionalSpouses.map { createCleanedPerson($0) },
            children: family.children.map { createCleanedPerson($0) },
            notes: family.notes,
            childrenDiedInfancy: family.childrenDiedInfancy
        )
    }
    
    private func createCleanedPerson(_ person: Person) -> Person {
        return Person(
            name: cleanName(person.name),
            patronymic: person.patronymic,
            birthDate: person.birthDate,
            deathDate: person.deathDate,
            marriageDate: person.marriageDate,
            spouse: person.spouse,
            asChildReference: person.asChildReference,
            asParentReference: person.asParentReference,
            familySearchId: person.familySearchId,
            noteMarkers: person.noteMarkers,
            fatherName: person.fatherName,
            motherName: person.motherName
        )
    }
    
    private func cleanName(_ name: String) -> String {
        let cleaned = name
        
        // Remove duplicate words like "Matti Matti_son" -> "Matti"
        let parts = cleaned.components(separatedBy: " ")
        var uniqueParts: [String] = []
        
        for part in parts {
            // Skip if this is a duplicate of the first name + suffix
            if !part.contains("_son") && !part.contains("_daughter") {
                if !uniqueParts.contains(part) {
                    uniqueParts.append(part)
                }
            }
        }
        
        return uniqueParts.joined(separator: " ")
    }
    
    // MARK: - Citation Generation
    
    func generateCitation(for person: Person, in family: Family) -> String {
        print("📄 Generating citation for: \(person.displayName)")
        
        // Check for as_child family
        if let asChildRef = person.asChildReference,
           let asChildFamily = mockFamilyDatabase[asChildRef] {
            return CitationGenerator.generateAsChildCitation(for: person, in: asChildFamily)
        }
        
        // Generate main family citation with improved formatting
        return generateImprovedMainFamilyCitation(family: family)
    }
    
    private func generateImprovedMainFamilyCitation(family: Family) -> String {
        var citation = "Information on page \(family.pageReferences.joined(separator: ", ")) includes:\n\n"
        
        // Father information
        citation += "\(family.father.name)"
        if let patronymic = family.father.patronymic {
            citation += " \(patronymic)"
        }
        if let birthDate = family.father.birthDate {
            citation += ", b \(normalizeDate(birthDate))"
        }
        if let deathDate = family.father.deathDate {
            citation += ", d \(normalizeDate(deathDate))"
        }
        citation += "\n"
        
        // Mother information
        if let mother = family.mother {
            citation += "\(mother.name)"
            if let patronymic = mother.patronymic {
                citation += " \(patronymic)"
            }
            if let birthDate = mother.birthDate {
                citation += ", b \(normalizeDate(birthDate))"
            }
            if let deathDate = mother.deathDate {
                citation += ", d \(normalizeDate(deathDate))"
            }
            citation += "\n"
        }
        
        // Marriage date (get from either parent)
        if let marriageDate = family.father.marriageDate ?? family.mother?.marriageDate {
            citation += "m \(normalizeDate(marriageDate))\n"
        }
        
        // Children
        if !family.children.isEmpty {
            citation += "\nChildren:\n"
            for child in family.children {
                citation += "\(child.name)"
                if let birthDate = child.birthDate {
                    citation += ", b \(normalizeDate(birthDate))"
                }
                if let marriageDate = child.marriageDate, let spouse = child.spouse {
                    citation += ", m \(spouse) \(normalizeDate(marriageDate))"
                }
                if let deathDate = child.deathDate {
                    citation += ", d \(normalizeDate(deathDate))"
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
        
        // Child mortality
        if let childrenDied = family.childrenDiedInfancy, childrenDied > 0 {
            citation += "\nChildren died in infancy: \(childrenDied)\n"
        }
        
        return citation
    }
    
    private func normalizeDate(_ date: String) -> String {
        // Convert DD.MM.YYYY to readable format
        let parts = date.components(separatedBy: ".")
        if parts.count == 3 {
            let day = parts[0]
            let month = parts[1]
            let year = parts[2]
            
            let months = ["", "January", "February", "March", "April", "May", "June",
                         "July", "August", "September", "October", "November", "December"]
            
            if let monthNum = Int(month), monthNum > 0 && monthNum <= 12 {
                return "\(Int(day) ?? 0) \(months[monthNum]) \(year)"
            }
        }
        
        return date // Return original if parsing fails
    }
    
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
    
    func generateHiskiQuery(for date: String, eventType: EventType) -> String {
        print("🔍 Generating Hiski query for: \(date) (\(eventType))")
        let cleanDate = date.replacingOccurrences(of: " ", with: "_")
        return "https://hiski.genealogia.fi/hiski?en+mock_query_\(eventType)_\(cleanDate)"
    }
    
    // MARK: - Mock Family Database
    
    private func createEnhancedMockFamilyDatabase() {
        mockFamilyDatabase["KORPI 5"] = createMockKorpi5()
        mockFamilyDatabase["SIKALA 5"] = createMockSikala5()
        mockFamilyDatabase["ISO-PEITSO III 2"] = createMockIsoPeitsoIII2()
        mockFamilyDatabase["ISO-PEITSO III 1"] = createMockIsoPeitsoIII1()
    }
    
    private func createMockKorpi5() -> Family {
        return Family(
            familyId: "KORPI 5",
            pageReferences: ["103", "104"],
            father: Person(name: "Erik", patronymic: "Matinp.", birthDate: "12.08.1685"),
            mother: Person(name: "Maija", patronymic: "Juhont.", birthDate: "08.10.1695"),
            additionalSpouses: [],
            children: [
                Person(name: "Matti", patronymic: "Erikinp.", birthDate: "09.09.1727", asParentReference: "KORPI 6")
            ],
            notes: [],
            childrenDiedInfancy: 2
        )
    }
    
    private func createMockSikala5() -> Family {
        return Family(
            familyId: "SIKALA 5",
            pageReferences: ["220", "221"],
            father: Person(name: "Matti", patronymic: "Antinp.", birthDate: "03.04.1700"),
            mother: Person(name: "Liisa", patronymic: "Pietarint.", birthDate: "12.12.1708"),
            additionalSpouses: [],
            children: [
                Person(name: "Brita", patronymic: "Matint.", birthDate: "05.09.1731", asParentReference: "KORPI 6")
            ],
            notes: [],
            childrenDiedInfancy: 1
        )
    }
    
    private func createMockIsoPeitsoIII2() -> Family {
        return Family(
            familyId: "ISO-PEITSO III 2",
            pageReferences: ["480", "481"],
            father: Person(name: "Elias", patronymic: "Juhonp.", birthDate: "15.03.1748"),
            mother: Person(name: "Maria", birthDate: "10.02.1752", deathDate: "22.01.1777"),
            additionalSpouses: [],
            children: [
                Person(name: "Juho", birthDate: "20.09.1774"),
                Person(name: "Anna", birthDate: "08.05.1776")
            ],
            notes: ["Maria kuoli synnytyksen jälkeen."],
            childrenDiedInfancy: 0
        )
    }
    
    private func createMockIsoPeitsoIII1() -> Family {
        return Family(
            familyId: "ISO-PEITSO III 1",
            pageReferences: ["478", "479"],
            father: Person(name: "Juho", patronymic: "Matinp.", birthDate: "20.01.1720"),
            mother: Person(name: "Katariina", patronymic: "Antint.", birthDate: "08.07.1725"),
            additionalSpouses: [],
            children: [
                Person(name: "Elias", patronymic: "Juhonp.", birthDate: "15.03.1748", asParentReference: "ISO-PEITSO III 2")
            ],
            notes: ["Iso-Peitso talo perustettu 1740."],
            childrenDiedInfancy: 1
        )
    }
}
