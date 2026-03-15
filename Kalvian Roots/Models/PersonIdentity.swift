//
//  PersonIdentity.swift
// Stable cross-source identity for a person.
//
// Used to match individuals across:
//
// - FamilySearch
// - Juuret Kälviällä
// - HisKi parish records
//
// Identity is defined by:
//
// - canonicalized first name
// - birth date
//
// Canonicalization is provided by NameEquivalenceManager.
//
//  Created by Michael Bendio on 3/14/26.
//

import Foundation

struct PersonIdentity: Hashable, CustomStringConvertible {

    // MARK: - Properties

    let canonicalName: String
    let birthDate: Date?

    // MARK: - Initialization

    init(name: String, birthDate: Date?, nameManager: NameEquivalenceManager) {

        self.canonicalName = nameManager.canonicalName(for: name)
        self.birthDate = birthDate
    }

    // MARK: - Matching

    /**
     Determines if two identities represent the same person.
     */

    func matches(_ other: PersonIdentity) -> Bool {

        guard canonicalName == other.canonicalName else {
            return false
        }

        switch (birthDate, other.birthDate) {

        case let (a?, b?):
            return a == b

        case (nil, _), (_, nil):
            // If birth date missing, fall back to name-only match
            return true
        }
    }

    // MARK: - Debugging

    var description: String {

        if let birthDate {

            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM yyyy"

            return "\(canonicalName) (\(formatter.string(from: birthDate)))"
        }

        return "\(canonicalName) (unknown birth)"
    }
}
