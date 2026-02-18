//
//  PersonLineView.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 10/8/25.
//

import SwiftUI

/**
 * Enhanced person line view with clickable elements and enhanced dates
 *
 * Phase 3 Implementation:
 * - Shows enhanced dates in brown [brackets] from asParent families
 * - All names, dates, and family IDs are clickable
 * - Matches the UI mockup appearance
 */
struct PersonLineView: View {
    let person: Person
    let network: FamilyNetwork?
    let onNameClick: (Person) -> Void
    let onDateClick: (String, EventType) -> Void
    let onSpouseDateClick: (String, EventType, SpouseEnhancedData) -> Void
    let onFamilyIdClick: (String) -> Void
    
    @State private var enhancedData: EnhancedPersonData?
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Star symbol
            Text("★")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.primary)
            
            // Birth date (clickable)
            if let birthDate = person.birthDate {
                clickableDate(birthDate, type: .birth)
            }
            
            // Name with patronymic (clickable)
            clickableName()
            
            // FamilySearch ID (non-clickable, angle brackets)
            if let fsId = person.familySearchId {
                Text("<\(fsId)>")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // asChild family ID (clickable, in braces) - FOR PARENTS
            if let asChild = person.asChild {
                Text("{")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.primary)
                
                clickableFamilyId(asChild)
                
                Text("}")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            // Death date (regular, not enhanced) - FOR PARENTS
            if let deathDate = person.deathDate, !person.isMarried {
                Text("†")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.primary)
                
                clickableDate(deathDate, type: .death)
            }
            
            // Enhanced death date (brown brackets) - FOR MARRIED CHILDREN
            if let deathDate = enhancedData?.deathDate {
                enhancedDeathDate(deathDate)
            }
            
            // Marriage symbol and enhanced date - FOR MARRIED CHILDREN
            if person.isMarried {
                marriageSection()
            }
            
            // asParent family ID (clickable) - FOR MARRIED CHILDREN
            if let familyId = person.asParent {
                clickableFamilyId(familyId)
            }
            
            // Note markers (* ** etc.)
            if !person.noteMarkers.isEmpty {
                Text(person.noteMarkers.joined(separator: " "))
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .font(.system(size: 16, design: .monospaced))
        .lineSpacing(1.3)
        .onAppear {
            loadEnhancedData()
        }
    }
    
    // MARK: - Enhanced Data Loading
    
    private func loadEnhancedData() {
        guard let network = network else { return }
        guard person.isMarried else { return }
        
        // Get asParent family for this person
        guard let asParentFamily = network.getAsParentFamily(for: person) else {
            return
        }
        
        // Find the matching person in asParent family
        guard let asParentPerson = findMatchingPerson(in: asParentFamily) else {
            return
        }
        
        // Find spouse enhanced data
        var spouseEnhancedData: SpouseEnhancedData?
        if let spouse = person.spouse {
            spouseEnhancedData = extractSpouseData(spouseName: spouse, from: asParentFamily, network: network)
        }
        
        // Extract enhanced dates
        enhancedData = EnhancedPersonData(
            deathDate: asParentPerson.deathDate,
            fullMarriageDate: asParentPerson.fullMarriageDate ?? asParentFamily.primaryCouple?.fullMarriageDate,
            spouse: spouseEnhancedData
        )
    }
    
    private func findMatchingPerson(in family: Family) -> Person? {
        // Try to find by birth date match (most reliable)
        if let birthDate = person.birthDate {
            if let match = family.allParents.first(where: { $0.birthDate == birthDate }) {
                return match
            }
        }
        
        // Try to find by name match
        let personNameLower = person.name.lowercased()
        if let match = family.allParents.first(where: { $0.name.lowercased() == personNameLower }) {
            return match
        }
        
        return nil
    }
    
    private func extractSpouseData(spouseName: String, from asParentFamily: Family, network: FamilyNetwork) -> SpouseEnhancedData? {
        // Find spouse in asParent family
        let spouseNameLower = spouseName.lowercased()
        guard let spouseInFamily = asParentFamily.allParents.first(where: {
            $0.name.lowercased().contains(spouseNameLower) || spouseNameLower.contains($0.name.lowercased())
        }) else {
            return nil
        }
        
        // Create temp spouse person to look up their asChild family
        let tempSpouse = Person(name: spouseInFamily.name, birthDate: spouseInFamily.birthDate, noteMarkers: [])
        
        // Get spouse's asChild family for their birth/death dates
        guard let spouseAsChildFamily = network.getSpouseAsChildFamily(for: tempSpouse) else {
            return SpouseEnhancedData(
                birthDate: spouseInFamily.birthDate,
                deathDate: spouseInFamily.deathDate,
                fullName: spouseName
            )
        }
        
        // Find spouse in their own asChild family
        if let spouseAsChild = spouseAsChildFamily.allChildren.first(where: {
            $0.name.lowercased() == spouseInFamily.name.lowercased() ||
            $0.birthDate == spouseInFamily.birthDate
        }) {
            return SpouseEnhancedData(
                birthDate: spouseAsChild.birthDate,
                deathDate: spouseAsChild.deathDate,
                fullName: spouseName
            )
        }
        
        return SpouseEnhancedData(
            birthDate: spouseInFamily.birthDate,
            deathDate: spouseInFamily.deathDate,
            fullName: spouseName
        )
    }
    
    // MARK: - Clickable Components
    
    private func clickableDate(_ date: String, type: EventType) -> some View {
        Button(action: {
            onDateClick(date, type)
        }) {
            Text(date)
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(Color(hex: "0066cc"))
        }
        .buttonStyle(.plain)
    }
    
    private func clickableName() -> some View {
        Button(action: {
            onNameClick(person)
        }) {
            Text(person.displayName)
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(Color(hex: "0066cc"))
        }
        .buttonStyle(.plain)
    }
    
    private func enhancedDeathDate(_ date: String) -> some View {
        HStack(spacing: 2) {
            Text("[d. ")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(Color(hex: "8b4513"))
            
            Button(action: {
                onDateClick(date, .death)
            }) {
                Text(date)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(Color(hex: "8b4513"))
            }
            .buttonStyle(.plain)
            
            Text("]")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(Color(hex: "8b4513"))
        }
    }
    
    private func marriageSection() -> some View {
        HStack(spacing: 4) {
            Text("∞")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.primary)
            
            // Enhanced marriage date (brown brackets) or regular date
            if let marriageDate = enhancedData?.fullMarriageDate ?? person.fullMarriageDate {
                HStack(spacing: 2) {
                    if enhancedData?.fullMarriageDate != nil {
                        // Enhanced date in brown brackets
                        Text("[")
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundColor(Color(hex: "8b4513"))
                    }
                    
                    Button(action: {
                        onDateClick(marriageDate, .marriage)
                    }) {
                        Text(marriageDate)
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundColor(enhancedData?.fullMarriageDate != nil ? Color(hex: "8b4513") : Color(hex: "0066cc"))
                    }
                    .buttonStyle(.plain)
                    
                    if enhancedData?.fullMarriageDate != nil {
                        Text("]")
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundColor(Color(hex: "8b4513"))
                    }
                }
            } else if let marriageDate = person.marriageDate {
                // Regular 2-digit marriage date (clickable blue)
                clickableDate(marriageDate, type: .marriage)
            }
            
            // Spouse name (clickable)
            if let spouse = person.spouse {
                Button(action: {
                    onNameClick(Person(name: spouse, noteMarkers: []))
                }) {
                    Text(spouse)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(Color(hex: "0066cc"))
                }
                .buttonStyle(.plain)
            }
            
            // Spouse enhanced dates (brown brackets)
            if let spouseData = enhancedData?.spouse {
                spouseEnhancedDates(spouseData)
            }
        }
    }
    
    private func spouseEnhancedDates(_ spouse: SpouseEnhancedData) -> some View {
        HStack(spacing: 2) {
            if let birthDate = spouse.birthDate, let deathDate = spouse.deathDate {
                // Date range format
                Text("[")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(Color(hex: "8b4513"))
                
                Button(action: {
                    onSpouseDateClick(birthDate, .birth, spouse)
                }) {
                    Text(birthDate)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(Color(hex: "8b4513"))
                }
                .buttonStyle(.plain)
                
                Text("-")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(Color(hex: "8b4513"))
                
                Button(action: {
                    onSpouseDateClick(deathDate, .death, spouse)
                }) {
                    Text(deathDate)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(Color(hex: "8b4513"))
                }
                .buttonStyle(.plain)
                
                Text("]")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(Color(hex: "8b4513"))
            } else if let birthDate = spouse.birthDate {
                // Birth only
                Text("[")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(Color(hex: "8b4513"))
                
                Button(action: {
                    onSpouseDateClick(birthDate, .birth, spouse)
                }) {
                    Text(birthDate)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(Color(hex: "8b4513"))
                }
                .buttonStyle(.plain)
                
                Text("]")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(Color(hex: "8b4513"))
            }
        }
    }
    
    private func clickableFamilyId(_ familyId: String) -> some View {
        // Check if this is a valid family ID (not a pseudo-family like "Loht. Vapola")
        let isValidId = FamilyIDs.isValid(familyId: familyId)
        
        if isValidId {
            return AnyView(
                Button(action: {
                    onFamilyIdClick(familyId)
                }) {
                    Text(familyId)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "0066cc"))
                }
                .buttonStyle(.plain)
            )
        } else {
            // Non-clickable pseudo-family ID in gray italic
            return AnyView(
                Text(familyId)
                    .font(.system(size: 16, design: .monospaced))
                    .italic()
                    .foregroundColor(.secondary)
            )
        }
    }
}

// MARK: - Supporting Data Structures

/**
 * Enhanced data extracted from asParent family
 */
struct EnhancedPersonData {
    let deathDate: String?
    let fullMarriageDate: String?
    let spouse: SpouseEnhancedData?
}

/**
 * Enhanced spouse data from spouse's asChild family
 */
struct SpouseEnhancedData {
    let birthDate: String?
    let deathDate: String?
    let fullName: String
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        // Married child with enhanced data
        PersonLineView(
            person: Person(
                name: "Magdalena",
                birthDate: "27.01.1759",
                marriageDate: "78",
                spouse: "Antti Korvela",
                asParent: "Korvela 3",
                noteMarkers: []
            ),
            network: nil,
            onNameClick: { _ in },
            onDateClick: { _, _ in },
            onSpouseDateClick: { _, _, _ in },
            onFamilyIdClick: { _ in }
        )
        
        // Unmarried child
        PersonLineView(
            person: Person(
                name: "Liisa",
                birthDate: "29.09.1773",
                noteMarkers: []
            ),
            network: nil,
            onNameClick: { _ in },
            onDateClick: { _, _ in },
            onSpouseDateClick: { _, _, _ in },
            onFamilyIdClick: { _ in }
        )
    }
    .padding()
    .background(Color(hex: "fefdf8"))
}
