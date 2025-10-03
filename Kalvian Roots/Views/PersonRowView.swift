//
//  PersonRowView.swift
//  Kalvian Roots
//
//  Display family members with enhanced dates; click to see citations
//

import SwiftUI

struct PersonRowView: View {
    let person: Person
    let role: String
    let enhancedDeathDate: String?  // NEW: Pass death date from asParent family
    let enhancedMarriageDate: String?  // NEW: Pass full marriage date from asParent family
    let onNameClick: (Person) -> Void
    let onDateClick: (String, EventType) -> Void
    let onSpouseClick: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Enhanced name (clickable for person's citation)
            Button(action: {
                onNameClick(person)
            }) {
                HStack {
                    Text("• \(person.displayName)")
                        .font(Font.system(size: 18))
                        .foregroundStyle(Color.primary)
                        .underline(true, color: Color.blue)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Enhanced dates and marriage (clickable)
            VStack(alignment: .leading, spacing: 4) {
                if let birthDate = person.birthDate {
                    dateButton(symbol: "★", date: birthDate, eventType: .birth)
                }
                
                // Show enhanced death date if available, otherwise fall back to person's death date
                if let deathDate = enhancedDeathDate ?? person.deathDate {
                    dateButton(symbol: "†", date: deathDate, eventType: .death)
                }
                
                // Show marriage info with enhanced date if available
                if let spouse = person.spouse {
                    marriageButton(spouse: spouse, enhancedDate: enhancedMarriageDate)
                }
            }
            .padding(.leading, 25)
        }
    }
    
    func marriageButton(spouse: String, enhancedDate: String?) -> some View {
        HStack(spacing: 6) {
            // Marriage symbol
            Text("∞")
                .font(Font.system(size: 15))
                .foregroundStyle(Color.primary)
            
            // Use enhanced date if available, otherwise fall back to person's dates
            let displayDate = enhancedDate ?? person.fullMarriageDate ?? person.marriageDate
            
            if let marriageDate = displayDate {
                // Marriage date (clickable for Hiski marriage query)
                Button(action: {
                    onDateClick(marriageDate, .marriage)
                }) {
                    Text(marriageDate)
                        .font(Font.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .underline(true, color: Color.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Spouse name (clickable for spouse's as_child citation)
            Button(action: {
                onSpouseClick(spouse)
            }) {
                Text(spouse)
                    .font(Font.system(size: 13))
                    .foregroundStyle(Color.primary)
                    .underline(true, color: Color.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    func dateButton(symbol: String, date: String, eventType: EventType) -> some View {
        HStack(spacing: 4) {
            Text(symbol)
                .font(Font.system(size: 15))
                .foregroundStyle(Color.primary)
            
            Button(action: {
                onDateClick(date, eventType)
            }) {
                Text(date)
                    .font(Font.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .underline(true, color: Color.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#Preview {
    PersonRowView(
        person: Person(
            name: "Maria",
            patronymic: "Jaakont.",
            birthDate: "27.03.1763",
            deathDate: nil,  // No death date in nuclear family
            marriageDate: "82",  // Only 2-digit in nuclear family
            spouse: "Matti Korpi"
        ),
        role: "Child",
        enhancedDeathDate: "28.07.1784",  // From asParent family
        enhancedMarriageDate: "08.11.1782",  // Full date from asParent family
        onNameClick: { _ in },
        onDateClick: { _, _ in },
        onSpouseClick: { _ in }
    )
    .padding()
}
