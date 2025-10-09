//
//  FamilyView.swift
//  Kalvian Roots
//
//  Enhanced family display with inline enhanced dates and clickable elements
//

import SwiftUI

struct FamilyView: View {
    @Environment(JuuretApp.self) private var juuretApp
    let family: Family
    let network: FamilyNetwork?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Family header with ID and pages
            familyHeader
            
            // Primary couple (parents)
            if let couple = family.primaryCouple {
                coupleSection(couple: couple, isAdditional: false)
            }
            
            // Additional couples (subsequent spouses)
            if family.couples.count > 1 {
                ForEach(Array(family.couples.dropFirst().enumerated()), id: \.offset) { index, couple in
                    additionalCoupleSection(couple: couple, spouseNumber: index + 2)
                }
            }
            
            // Family notes
            if !family.notes.isEmpty {
                notesSection
            }
        }
        .font(.system(size: 16, design: .monospaced))
        .padding()
        .background(Color(hex: "fefdf8"))
    }
    
    // MARK: - Family Header
    
    private var familyHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Family ID - clickable to navigate
            Button(action: {
                // Already viewing this family, but could show info
            }) {
                Text(family.familyId)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "0066cc"))
            }
            .buttonStyle(.plain)
            
            // Page references
            Text("Pages: \(family.pageReferences.joined(separator: ", "))")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 12)
    }
    
    // MARK: - Couple Section
    
    private func coupleSection(couple: Couple, isAdditional: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Father
            personLine(person: couple.husband, symbol: "★")
            
            // Mother
            personLine(person: couple.wife, symbol: "★")
            
            // Marriage date
            if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
                marriageLine(date: marriageDate)
            }
            
            // Children header
            if !couple.children.isEmpty {
                Text("Lapset")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                // Children
                ForEach(couple.children) { child in
                    childLine(child: child)
                }
            }
            
            // Children died in infancy
            if let childrenDied = couple.childrenDiedInfancy, childrenDied > 0 {
                Text("Lapsena kuollut \(childrenDied).")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 12)
    }
    
    private func additionalCoupleSection(couple: Couple, spouseNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Spouse indicator
            Text(romanNumeral(spouseNumber) + " puoliso")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            // Additional spouse info
            personLine(person: couple.wife, symbol: "★")
            
            // Marriage date
            if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
                marriageLine(date: marriageDate)
            }
            
            // Children with this spouse
            if !couple.children.isEmpty {
                Text("Lapset")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                ForEach(couple.children) { child in
                    childLine(child: child)
                }
            }
        }
        .padding(.bottom, 12)
    }
    
    // MARK: - Person Lines
    
    private func personLine(person: Person, symbol: String) -> some View {
        HStack(spacing: 4) {
            // Birth symbol and date
            Text(symbol)
                .foregroundColor(.primary)
            
            if let birthDate = person.birthDate {
                clickableDate(birthDate, eventType: .birth, person: person)
            }
            
            // Name (clickable)
            clickableName(person)
            
            // FamilySearch ID
            if let fsId = person.familySearchId {
                Text("<\(fsId)>")
                    .foregroundColor(.secondary)
            }
            
            // as_child family reference (clickable)
            if let asChild = person.asChild {
                familyIdLink(asChild)
            }
            
            // Death date
            if let deathDate = person.deathDate {
                Text("†")
                    .foregroundColor(.primary)
                clickableDate(deathDate, eventType: .death, person: person)
            }
            
            Spacer()
        }
    }
    
    private func childLine(child: Person) -> some View {
        HStack(spacing: 4) {
            // Birth symbol and date
            Text("★")
                .foregroundColor(.primary)
            
            if let birthDate = child.birthDate {
                clickableDate(birthDate, eventType: .birth, person: child)
            }
            
            // Name (clickable)
            clickableName(child)
            
            // Enhanced death date (from asParent family)
            if let enhancedDeath = getEnhancedDeathDate(for: child) {
                Text("[d.")
                    .foregroundColor(Color(hex: "8b4513"))
                clickableDate(enhancedDeath, eventType: .death, person: child, enhanced: true)
                Text("]")
                    .foregroundColor(Color(hex: "8b4513"))
            }
            
            // FamilySearch ID
            if let fsId = child.familySearchId {
                Text("<\(fsId)>")
                    .foregroundColor(.secondary)
            }
            
            // Marriage info (if married)
            if child.isMarried {
                Text("∞")
                    .foregroundColor(.primary)
                
                // Enhanced marriage date (from asParent family)
                if let enhancedMarriage = getEnhancedMarriageDate(for: child) {
                    Text("[")
                        .foregroundColor(Color(hex: "8b4513"))
                    clickableDate(enhancedMarriage, eventType: .marriage, person: child, enhanced: true)
                    Text("]")
                        .foregroundColor(Color(hex: "8b4513"))
                } else if let marriageDate = child.fullMarriageDate ?? child.marriageDate {
                    clickableDate(marriageDate, eventType: .marriage, person: child)
                }
                
                // Spouse name (clickable)
                if let spouseName = child.spouse {
                    clickableSpouse(spouseName, forChild: child)
                    
                    // Enhanced spouse dates (from spouse's asChild family)
                    if let spouseDates = getEnhancedSpouseDates(forChild: child) {
                        Text("[")
                            .foregroundColor(Color(hex: "8b4513"))
                        Text(spouseDates)
                            .foregroundColor(Color(hex: "8b4513"))
                        Text("]")
                            .foregroundColor(Color(hex: "8b4513"))
                    }
                    
                    // Spouse FamilySearch ID (from spouse's asChild family)
                    if let spouseFsId = getSpouseFamilySearchId(forChild: child) {
                        Text("<\(spouseFsId)>")
                            .foregroundColor(.secondary)
                    }                }
                
                // asParent family reference (clickable)
                if let asParent = child.asParent {
                    familyIdLink(asParent)
                }
            }
            
            Spacer()
        }
        .lineSpacing(0)
    }
    
    private func marriageLine(date: String) -> some View {
        HStack(spacing: 4) {
            Text("∞")
                .foregroundColor(.primary)
            clickableDate(date, eventType: .marriage, person: nil)
            Spacer()
        }
    }
    
    // MARK: - Clickable Elements
    
    private func clickableName(_ person: Person) -> some View {
        Button(action: {
            generateCitation(for: person)
        }) {
            Text(person.displayName)
                .foregroundColor(Color(hex: "0066cc"))
                .underline()
        }
        .buttonStyle(.plain)
    }
    
    private func clickableDate(_ date: String, eventType: EventType, person: Person?, enhanced: Bool = false) -> some View {
        Button(action: {
            if let person = person {
                queryHiski(for: person, eventType: eventType)
            }
        }) {
            Text(date)
                .foregroundColor(enhanced ? Color(hex: "8b4513") : Color(hex: "0066cc"))
                .underline()
        }
        .buttonStyle(.plain)
    }
    
    private func clickableSpouse(_ spouseName: String, forChild child: Person) -> some View {
        Button(action: {
            generateSpouseCitation(spouseName)
        }) {
            Text(spouseName)
                .foregroundColor(Color(hex: "0066cc"))
                .underline()
        }
        .buttonStyle(.plain)
    }
    
    private func familyIdLink(_ familyId: String) -> some View {
        Button(action: {
            navigateToFamily(familyId)
        }) {
            Text("{\(familyId)}")
                .foregroundColor(Color(hex: "0066cc"))
                .fontWeight(.medium)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(family.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Enhanced Data Extraction
    
    private func getEnhancedDeathDate(for child: Person) -> String? {
        guard let network = network,
              let asParentFamily = network.getAsParentFamily(for: child) else {
            return nil
        }
        
        // Find the child as a parent in their asParent family
        let asParentPerson = asParentFamily.allParents.first { parent in
            parent.name.lowercased() == child.name.lowercased() ||
            (parent.birthDate == child.birthDate && parent.birthDate != nil)
        }
        
        // Return enhanced death date only if it's different from nuclear family
        if let enhancedDeath = asParentPerson?.deathDate,
           enhancedDeath != child.deathDate {
            return enhancedDeath
        }
        
        return nil
    }
    
    private func getEnhancedMarriageDate(for child: Person) -> String? {
        guard let network = network,
              let asParentFamily = network.getAsParentFamily(for: child) else {
            return nil
        }
        
        // Find the couple in asParent family
        let couple = asParentFamily.couples.first { couple in
            couple.husband.name.lowercased() == child.name.lowercased() ||
            couple.wife.name.lowercased() == child.name.lowercased()
        }
        
        // Return enhanced marriage date (prefer full date)
        let enhancedMarriage = couple?.fullMarriageDate ?? couple?.marriageDate
        let nuclearMarriage = child.fullMarriageDate ?? child.marriageDate
        
        // Return only if enhanced is different and better
        if let enhanced = enhancedMarriage,
           enhanced != nuclearMarriage,
           enhanced.count >= 8 { // Prefer full 8-digit dates
            return enhanced
        }
        
        return nil
    }
    
    private func getEnhancedSpouseDates(forChild child: Person) -> String? {
        guard let network = network,
              let spouseName = child.spouse else {
            return nil
        }
        
        // Find spouse's asChild family
        let spousePerson = Person(name: spouseName, noteMarkers: [])
        guard let spouseFamily = network.getSpouseAsChildFamily(for: spousePerson) else {
            return nil
        }
        
        // Find the spouse in their asChild family
        let spouseInFamily = spouseFamily.allChildren.first { person in
            person.name.lowercased().contains(spouseName.split(separator: " ").first?.lowercased() ?? "")
        }
        
        // Build date range string
        var dates: [String] = []
        if let birthDate = spouseInFamily?.birthDate {
            dates.append(birthDate)
        }
        if let deathDate = spouseInFamily?.deathDate {
            dates.append(deathDate)
        }
        
        return dates.isEmpty ? nil : dates.joined(separator: "-")
    }
    
    private func getSpouseFamilySearchId(forChild child: Person) -> String? {
        guard let network = network,
              let spouseName = child.spouse else {
            return nil
        }
        
        // Create a Person object for the spouse to look up their family
        let spousePerson = Person(name: spouseName, noteMarkers: [])
        guard let spouseFamily = network.getSpouseAsChildFamily(for: spousePerson) else {
            return nil
        }
        
        // Find the spouse in their asChild family
        let spouseInFamily = spouseFamily.allChildren.first { person in
            person.name.lowercased().contains(spouseName.split(separator: " ").first?.lowercased() ?? "")
        }
        
        return spouseInFamily?.familySearchId
    }
    
    // MARK: - Actions
    
    private func generateCitation(for person: Person) {
        Task {
            let citation = await juuretApp.generateCitation(for: person, in: family)
            // Show citation in alert/sheet (handled by parent view)
            await MainActor.run {
                // Trigger parent view's citation display
            }
        }
    }
    
    private func generateSpouseCitation(_ spouseName: String) {
        Task {
            let citation = await juuretApp.generateSpouseCitation(for: spouseName, in: family)
            // Show citation (handled by parent view)
        }
    }
    
    private func queryHiski(for person: Person, eventType: EventType) {
        Task {
            let result = await juuretApp.processHiskiQuery(
                for: person,
                eventType: eventType,
                familyId: family.familyId
            )
            // Show result (handled by parent view)
        }
    }
    
    private func navigateToFamily(_ familyId: String) {
        // Navigate without updating history (content navigation)
        juuretApp.navigateToFamily(familyId, updateHistory: false)
    }
    
    // MARK: - Helpers
    
    private func romanNumeral(_ number: Int) -> String {
        switch number {
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        default: return String(number)
        }
    }
}

// MARK: - Preview

#Preview {
    FamilyView(
        family: Family.sampleFamily(),
        network: nil
    )
    .environment(JuuretApp())
}
