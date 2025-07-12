//
//  Person.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import FoundationModels

@Generable
struct Person: Hashable, Sendable {
    var name: String
    var patronymic: String?
    var birthDate: String?
    var deathDate: String?
    var marriageDate: String?
    var spouse: String?
    var asChildReference: String?
    var asParentReference: String?
    var familySearchId: String?
    var noteMarkers: [String]
    
    var displayName: String {
        if let patronymic = patronymic {
            return "\(name) \(patronymic)"
        }
        return name
    }
}
