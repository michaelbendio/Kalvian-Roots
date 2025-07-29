//
//  PersonRowView.swift - UPDATED with Enhanced Fonts
//  Kalvian Roots
//
//  Enhanced genealogical person display with larger, more readable fonts
//

import SwiftUI

struct PersonRowView: View {
    let person: Person
    let role: String
    let onNameClick: (Person) -> Void
    let onDateClick: (String, EventType) -> Void
    let onSpouseClick: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { // Increased spacing
            // Enhanced name (clickable for person's citation)
            Button(action: {
                onNameClick(person)
            }) {
                HStack {
                    Text("• \(person.displayName)")
                        .foregroundColor(.blue)
                        .underline()
                        .font(.genealogySubheadline) // Enhanced font (18pt)
                    Text("(\(role))")
                        .font(.genealogyCallout) // Enhanced font (14pt)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Enhanced dates and marriage (clickable)
            VStack(alignment: .leading, spacing: 4) { // Increased spacing
                if let birthDate = person.birthDate {
                    dateButton(symbol: "★", date: birthDate, eventType: .birth)
                }
                
                if let deathDate = person.deathDate {
                    dateButton(symbol: "†", date: deathDate, eventType: .death)
                }
                
                if let marriageDate = person.marriageDate, let spouse = person.spouse {
                    marriageButton(marriageDate: marriageDate, spouse: spouse)
                }
            }
            .padding(.leading, 25) // Increased padding for better indentation
        }
    }
    
    func dateButton(symbol: String, date: String, eventType: EventType) -> some View {
        Button(action: {
            onDateClick(date, eventType)
        }) {
            HStack {
                Text(symbol)
                    .foregroundColor(.primary)
                    .font(.genealogyCallout) // Enhanced font (14pt)
                Text(date)
                    .foregroundColor(.blue)
                    .underline()
                    .font(.genealogyMonospaceSmall) // Enhanced monospace font (14pt)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func marriageButton(marriageDate: String, spouse: String) -> some View {
        HStack(spacing: 6) { // Increased spacing
            // Marriage symbol
            Text("∞")
                .foregroundColor(.primary)
                .font(.genealogyCallout) // Enhanced font (14pt)
            
            // Marriage date (clickable for Hiski marriage query)
            Button(action: {
                onDateClick(marriageDate, .marriage)
            }) {
                Text(marriageDate)
                    .foregroundColor(.blue)
                    .underline()
                    .font(.genealogyMonospaceSmall) // Enhanced monospace font (14pt)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Spouse name - Purple ONLY for children who have spouses
            // Parents (Matti & Brita) will show spouse name but not be clickable
            if shouldShowSpouseAsClickable() {
                Button(action: {
                    onSpouseClick(spouse)
                }) {
                    Text(spouse)
                        .foregroundColor(.purple)
                        .underline()
                        .font(.genealogyCallout) // Enhanced font (14pt)
                        .fontWeight(.medium)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text(spouse)
                    .foregroundColor(.primary)
                    .font(.genealogyCallout) // Enhanced font (14pt)
            }
        }
    }
    
    // Only show spouse as clickable for children, not parents
    func shouldShowSpouseAsClickable() -> Bool {
        return role == "Child"
    }
}
