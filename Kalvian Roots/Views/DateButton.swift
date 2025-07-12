//
//  DateButton.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import SwiftUI

struct DateButton: View {
    let symbol: String
    let date: String
    let eventType: EventType
    let onDateClick: (String, EventType) -> Void
    
    var body: some View {
        Button(action: { onDateClick(date, eventType) }) {
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
}
