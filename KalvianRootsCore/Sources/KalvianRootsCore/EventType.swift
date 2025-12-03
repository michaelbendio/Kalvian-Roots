//
//  EventType.swift
//  Kalvian Roots
//
//  Complete event types for genealogical records and Hiski queries
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation

/**
 * Event types for genealogical records and church record queries
 */
public enum EventType: String, CaseIterable {
    case birth = "birth"
    case death = "death"
    case marriage = "marriage"
    case baptism = "baptism"
    case burial = "burial"
    
    public var displayName: String {
        switch self {
        case .birth:
            return "Birth"
        case .death:
            return "Death"
        case .marriage:
            return "Marriage"
        case .baptism:
            return "Baptism"
        case .burial:
            return "Burial"
        }
    }
    
    public var symbol: String {
        switch self {
        case .birth:
            return "★"
        case .death:
            return "†"
        case .marriage:
            return "∞"
        case .baptism:
            return "✝"
        case .burial:
            return "⚱"
        }
    }
}
