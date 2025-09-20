//
//  PersonRowView.swift
//  Kalvian Roots
//
//  Display family members; click to see citations
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
                        .font(Font.system(size: 18))
                        .foregroundStyle(Color.primary)  // Changed to black
                        .underline(true, color: Color.blue)  // Added blue underline
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
    
    func marriageButton(marriageDate: String, spouse: String) -> some View {
        HStack(spacing: 6) {
            // Marriage symbol
            Text("∞")
                .font(Font.system(size: 15))
                .foregroundStyle(Color.primary)
            
            // Marriage date (clickable for Hiski marriage query)
            Button(action: {
                onDateClick(marriageDate, .marriage)
            }) {
                Text(marriageDate)
                    .font(Font.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.primary)  // Changed to black
                    .underline(true, color: Color.blue)  // Added blue underline
            }
            .buttonStyle(PlainButtonStyle())
            
            // Spouse name - Always clickable, black with blue underline
            Button(action: {
                onSpouseClick(spouse)
            }) {
                Text(spouse)
                    .font(Font.system(size: 15))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.primary)  // Changed from purple to black
                    .underline(true, color: Color.blue)  // Changed underline to blue
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    func dateButton(symbol: String, date: String, eventType: EventType) -> some View {
        Button(action: {
            onDateClick(date, eventType)
        }) {
            HStack {
                Text(symbol)
                    .font(Font.system(size: 15))
                    .foregroundStyle(Color.primary)
                Text(date)
                    .font(Font.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.primary)  // Changed to black
                    .underline(true, color: Color.blue)  // Added blue underline
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
