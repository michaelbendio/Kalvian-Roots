//
//  PersonRowView.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import SwiftUI

struct PersonRowView: View {
    let person: Person
    let role: String
    let onNameClick: (Person) -> Void
    let onDateClick: (String, EventType) -> Void
    let onSpouseClick: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Name (clickable for person's citation)
            Button(action: {
                onNameClick(person)
            }) {
                HStack {
                    Text("• \(person.displayName)")
                        .foregroundColor(.blue)
                        .underline()
                    Text("(\(role))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Dates and Marriage (clickable)
            VStack(alignment: .leading, spacing: 2) {
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
            .padding(.leading, 20)
        }
    }
    
    func dateButton(symbol: String, date: String, eventType: EventType) -> some View {
        Button(action: {
            onDateClick(date, eventType)
        }) {
            HStack {
                Text(symbol)
                    .foregroundColor(.primary)
                Text(date)
                    .foregroundColor(.blue)
                    .underline()
            }
            .font(.caption)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func marriageButton(marriageDate: String, spouse: String) -> some View {
        HStack(spacing: 4) {
            // Marriage symbol
            Text("∞")
                .foregroundColor(.primary)
                .font(.caption)
            
            // Marriage date (clickable for Hiski marriage query)
            Button(action: {
                onDateClick(marriageDate, .marriage)
            }) {
                Text(marriageDate)
                    .foregroundColor(.blue)
                    .underline()
                    .font(.caption)
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
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text(spouse)
                    .foregroundColor(.primary)
                    .font(.caption)
            }
        }
    }
    
    // Only show spouse as clickable for children, not parents
    func shouldShowSpouseAsClickable() -> Bool {
        return role == "Child"
    }
}
