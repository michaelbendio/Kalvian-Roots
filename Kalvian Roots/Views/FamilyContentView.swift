//
//  FamilyContentView.swift
//  Kalvian Roots
//
//  Phase 4: Family Display Layout with authentic monospace appearance
//  Matches the UI mockup specification
//

import SwiftUI

/**
 * Family content display with authentic genealogy book appearance
 *
 * Phase 4 Implementation:
 * - Monospace font throughout (like Courier New)
 * - Tight line spacing (1.3) matching the mockup
 * - Off-white background (#fefdf8) for warmth
 * - Proper family structure ordering
 * - Minimal gaps between sections for density
 */
struct FamilyContentView: View {
    @Environment(JuuretApp.self) private var juuretApp
    let family: Family
    
    // Citation and Hiski handlers
    let onShowCitation: (String) -> Void
    let onShowHiski: (String) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Family ID + page references
                familyHeader
                    .padding(.bottom, 12)
                
                // 2. Parent lines (primary couple)
                if let couple = family.primaryCouple {
                    parentLines(couple: couple)
                    
                    // 3. Marriage date line
                    if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
                        marriageLine(date: marriageDate)
                            .padding(.top, 2)
                    }
                    
                    // 4. "Lapset" header + children
                    if !couple.children.isEmpty {
                        childrenSection(children: couple.children)
                            .padding(.top, 8)
                    }
                    
                    // Children died in infancy
                    if let died = couple.childrenDiedInfancy, died > 0 {
                        Text("Lapsena kuollut \(died).")
                            .applyFamilyLineStyle()
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.top, 4)
                    }
                }
                
                // 6. Additional spouses (II puoliso, III puoliso, etc.)
                if family.couples.count > 1 {
                    additionalSpouses()
                        .padding(.top, 12)
                }
                
                // 7. Notes
                if !family.notes.isEmpty {
                    notesSection()
                        .padding(.top, 12)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(hex: "fefdf8"))
    }
    
    // MARK: - Family Header
    
    private var familyHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Family ID
            Text(family.familyId)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
            
            // Page references
            if !family.pageReferences.isEmpty {
                Text("Pages \(family.pageReferences.joined(separator: ", "))")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }
    
    // MARK: - Parent Lines
    
    private func parentLines(couple: Couple) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Father line
            PersonLineView(
                person: couple.husband,
                network: juuretApp.familyNetworkWorkflow?.getFamilyNetwork(),
                onNameClick: { person in
                    generateCitationFor(person)
                },
                onDateClick: { date, eventType in
                    generateHiskiFor(person: couple.husband, date: date, eventType: eventType)
                },
                onSpouseDateClick: { _, _, _ in },
                onFamilyIdClick: { familyId in
                    juuretApp.navigateToFamily(familyId, updateHistory: false)
                }
            )
            
            // Mother line
            PersonLineView(
                person: couple.wife,
                network: juuretApp.familyNetworkWorkflow?.getFamilyNetwork(),
                onNameClick: { person in
                    generateCitationFor(person)
                },
                onDateClick: { date, eventType in
                    generateHiskiFor(person: couple.wife, date: date, eventType: eventType)
                },
                onSpouseDateClick: { _, _, _ in },
                onFamilyIdClick: { familyId in
                    juuretApp.navigateToFamily(familyId, updateHistory: false)
                }
            )
        }
    }
    
    // MARK: - Marriage Line
    
    private func marriageLine(date: String) -> some View {
        HStack(spacing: 4) {
            Text("∞")
                .applyFamilyLineStyle()
            
            Button(action: {
                // Marriage date click -> Hiski
                Task {
                    let result = await juuretApp.processHiskiQuery(
                        for: family.primaryCouple?.husband ?? family.primaryCouple!.wife,
                        eventType: EventType.marriage,
                        familyId: family.familyId,
                        explicitDate: date
                    )
                    onShowHiski(result)
                }
            }) {
                Text(date)
                    .applyFamilyLineStyle()
                    .foregroundColor(Color(hex: "0066cc"))
            }
            .buttonStyle(.plain)
            
            Text(".")
                .applyFamilyLineStyle()
        }
    }
    
    // MARK: - Children Section
    
    private func childrenSection(children: [Person]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // "Lapset" header
            Text("Lapset")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.bottom, 2)
            
            // Child lines
            ForEach(children) { child in
                PersonLineView(
                    person: child,
                    network: juuretApp.familyNetworkWorkflow?.getFamilyNetwork(),
                    onNameClick: { person in
                        generateCitationFor(person)
                    },
                    onDateClick: { date, eventType in
                        generateHiskiFor(person: child, date: date, eventType: eventType)
                    },
                    onSpouseDateClick: { date, eventType, spouseData in
                        let spousePerson = Person(name: spouseData.fullName, birthDate: spouseData.birthDate, deathDate: spouseData.deathDate, noteMarkers: [])
                        generateHiskiFor(person: spousePerson, date: date, eventType: eventType)
                    },
                    onFamilyIdClick: { familyId in
                        juuretApp.navigateToFamily(familyId, updateHistory: false)
                    }
                )
            }
        }
    }
    
    // MARK: - Additional Spouses
    
    private func additionalSpouses() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(family.couples.dropFirst().enumerated()), id: \.offset) { index, couple in
                additionalSpouseSection(couple: couple, spouseNumber: index + 2)
            }
        }
    }
    
    private func additionalSpouseSection(couple: Couple, spouseNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Spouse header (II puoliso, III puoliso, etc.)
            Text("\(romanNumeral(spouseNumber)) puoliso")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.top, 4)
            
            // Determine which person is the new spouse
            let previousCouple = family.couples[spouseNumber - 2]
            let isHusbandContinuing = couple.husband.name == previousCouple.husband.name &&
                                      couple.husband.birthDate == previousCouple.husband.birthDate
            
            let additionalSpouse = isHusbandContinuing ? couple.wife : couple.husband
            
            // Additional spouse line
            PersonLineView(
                person: additionalSpouse,
                network: juuretApp.familyNetworkWorkflow?.getFamilyNetwork(),
                onNameClick: { person in
                    generateCitationFor(person)
                },
                onDateClick: { date, eventType in
                    generateHiskiFor(person: additionalSpouse, date: date, eventType: eventType)
                },
                onSpouseDateClick: { _, _, _ in },
                onFamilyIdClick: { familyId in
                    juuretApp.navigateToFamily(familyId, updateHistory: false)
                }
            )
            
            // Marriage date for this couple
            if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
                marriageLine(date: marriageDate)
                    .padding(.top, 2)
            }
            
            // Children with this spouse
            if !couple.children.isEmpty {
                childrenSection(children: couple.children)
                    .padding(.top, 4)
            }
            
            // Children died in infancy for this couple
            if let died = couple.childrenDiedInfancy, died > 0 {
                Text("Lapsena kuollut \(died).")
                    .applyFamilyLineStyle()
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Notes Section
    
    private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(family.notes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .applyFamilyLineStyle()
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateCitationFor(_ person: Person) {
        Task {
            let citation = await juuretApp.generateCitation(for: person, in: family)
            onShowCitation(citation)
        }
    }
    
    private func generateHiskiFor(person: Person, date: String, eventType: EventType) {
        Task {
            let result = await juuretApp.processHiskiQuery(
                for: person,
                eventType: eventType,
                familyId: family.familyId,
                explicitDate: date
            )
            onShowHiski(result)
        }
    }
    private func romanNumeral(_ number: Int) -> String {
        switch number {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        case 5: return "V"
        case 6: return "VI"
        case 7: return "VII"
        case 8: return "VIII"
        case 9: return "IX"
        case 10: return "X"
        default: return "\(number)"
        }
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply consistent family line styling
    func applyFamilyLineStyle() -> some View {
        self
            .font(.system(size: 16, design: .monospaced))
            .lineSpacing(1.3)
    }
}

// MARK: - Preview

#Preview {
    let sampleFamily = Family.sampleFamily()
    
    return FamilyContentView(
        family: sampleFamily,
        onShowCitation: { citation in
            print("Citation: \(citation)")
        },
        onShowHiski: { hiski in
            print("Hiski: \(hiski)")
        }
    )
    .environment(JuuretApp())
}
