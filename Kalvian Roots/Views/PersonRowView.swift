//
//  PersonRowView.swift - Fixed for SwiftUI API Changes
//  Kalvian Roots
//
//  Enhanced genealogical person display with SwiftUI compatibility fixes
//

import SwiftUI

struct PersonRowView: View {
    let person: Person
    let role: String
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
                        .font(Font.system(size: 18))  // FIXED: Direct system font
                        .foregroundStyle(Color.blue)
                        .underline(true, color: Color.blue)
                    Text("(\(role))")
                        .font(Font.system(size: 15))  // FIXED: Direct system font
                        .foregroundStyle(Color.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Enhanced dates and marriage (clickable)
            VStack(alignment: .leading, spacing: 4) {
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
            .padding(.leading, 25)
        }
    }
    
    func dateButton(symbol: String, date: String, eventType: EventType) -> some View {
        Button(action: {
            onDateClick(date, eventType)
        }) {
            HStack {
                Text(symbol)
                    .font(Font.system(size: 15))  // FIXED: Direct system font
                    .foregroundStyle(Color.primary)
                Text(date)
                    .font(Font.system(size: 13, design: .monospaced))  // FIXED: Direct system font
                    .foregroundStyle(Color.blue)
                    .underline(true, color: Color.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func marriageButton(marriageDate: String, spouse: String) -> some View {
        HStack(spacing: 6) {
            // Marriage symbol
            Text("∞")
                .font(Font.system(size: 15))  // FIXED: Direct system font
                .foregroundStyle(Color.primary)
            
            // Marriage date (clickable for Hiski marriage query)
            Button(action: {
                onDateClick(marriageDate, .marriage)
            }) {
                Text(marriageDate)
                    .font(Font.system(size: 13, design: .monospaced))  // FIXED: Direct system font
                    .foregroundStyle(Color.blue)
                    .underline(true, color: Color.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Spouse name - Purple ONLY for children who have spouses
            // Parents (Matti & Brita) will show spouse name but not be clickable
            if shouldShowSpouseAsClickable() {
                Button(action: {
                    onSpouseClick(spouse)
                }) {
                    Text(spouse)
                        .font(Font.system(size: 15))  // FIXED: Direct system font
                        .fontWeight(.medium)
                        .foregroundStyle(Color.purple)
                        .underline(true, color: Color.purple)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text(spouse)
                    .font(Font.system(size: 15))  // FIXED: Direct system font
                    .foregroundStyle(Color.primary)
            }
        }
    }
    
    // Only show spouse as clickable for children, not parents
    func shouldShowSpouseAsClickable() -> Bool {
        return role == "Child"
    }
}

// Note: Font sizes used in this view:
// - Display names: 18pt (genealogySubheadline equivalent)
// - Role labels and regular text: 15pt (genealogyCallout equivalent)
// - Dates: 13pt monospaced (genealogyMonospaceSmall equivalent)
