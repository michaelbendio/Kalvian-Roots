//
//  Family.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import FoundationModels

@Generable
struct Family: Hashable, Sendable {
    var familyId: String
    var pageReferences: [String]
    var father: Person
    var mother: Person?
    var additionalSpouses: [Person]
    var children: [Person]
    var notes: [String]
    var childrenDiedInfancy: Int?
}
