//
//  HiskiQuery.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/29/25.
//

import Foundation

/**
 * HiskiQuery - Finnish church record query structure
 *
 * Generates URLs for querying the Hiski genealogical database (hiski.genealogia.fi)
 * for Finnish church records including births, deaths, marriages, baptisms, and burials.
 */
enum HiskiQuery {
    case birth(childName: String, birthDate: String, fatherName: String?, motherName: String?)
    case death(personName: String, deathDate: String)
    case marriage(spouseName1: String, spouseName2: String, marriageDate: String)
    case baptism(childName: String, baptismDate: String, fatherName: String?, motherName: String?)
    case burial(personName: String, burialDate: String)
    
    /// Generate the Hiski query URL
    var queryURL: String {
        let baseURL = "https://hiski.genealogia.fi/hiski"
        
        switch self {
        case .birth(let childName, let birthDate, let fatherName, let motherName):
            var params = "?et=birth&child=\(childName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            params += "&date=\(birthDate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            
            if let father = fatherName {
                params += "&father=\(father.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
            
            if let mother = motherName {
                params += "&mother=\(mother.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
            
            return baseURL + params
            
        case .death(let personName, let deathDate):
            let params = "?et=death&person=\(personName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            + "&date=\(deathDate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            return baseURL + params
            
        case .marriage(let spouse1, let spouse2, let marriageDate):
            let params = "?et=marriage&spouse1=\(spouse1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            + "&spouse2=\(spouse2.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            + "&date=\(marriageDate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            return baseURL + params
            
        case .baptism(let childName, let baptismDate, let fatherName, let motherName):
            var params = "?et=baptism&child=\(childName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            params += "&date=\(baptismDate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            
            if let father = fatherName {
                params += "&father=\(father.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
            
            if let mother = motherName {
                params += "&mother=\(mother.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
            
            return baseURL + params
            
        case .burial(let personName, let burialDate):
            let params = "?et=burial&person=\(personName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            + "&date=\(burialDate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            return baseURL + params
        }
    }
    
    /// Human-readable description of the query
    var description: String {
        switch self {
        case .birth(let childName, let birthDate, _, _):
            return "Birth record for \(childName) on \(birthDate)"
        case .death(let personName, let deathDate):
            return "Death record for \(personName) on \(deathDate)"
        case .marriage(let spouse1, let spouse2, let marriageDate):
            return "Marriage record for \(spouse1) and \(spouse2) on \(marriageDate)"
        case .baptism(let childName, let baptismDate, _, _):
            return "Baptism record for \(childName) on \(baptismDate)"
        case .burial(let personName, let burialDate):
            return "Burial record for \(personName) on \(burialDate)"
        }
    }
    
    /// Create appropriate HiskiQuery from Person and EventType
    static func from(person: Person, eventType: EventType) -> HiskiQuery? {
        switch eventType {
        case .birth:
            guard let birthDate = person.birthDate else { return nil }
            return .birth(
                childName: person.name,
                birthDate: birthDate,
                fatherName: person.fatherName,
                motherName: person.motherName
            )
            
        case .death:
            guard let deathDate = person.deathDate else { return nil }
            return .death(
                personName: person.displayName,
                deathDate: deathDate
            )
            
        case .marriage:
            guard let marriageDate = person.bestMarriageDate,
                  let spouse = person.spouse else { return nil }
            return .marriage(
                spouseName1: person.displayName,
                spouseName2: spouse,
                marriageDate: marriageDate
            )
            
        case .baptism:
            // Use birth date for baptism if available
            guard let birthDate = person.birthDate else { return nil }
            return .baptism(
                childName: person.name,
                baptismDate: birthDate,
                fatherName: person.fatherName,
                motherName: person.motherName
            )
            
        case .burial:
            // Use death date for burial if available
            guard let deathDate = person.deathDate else { return nil }
            return .burial(
                personName: person.displayName,
                burialDate: deathDate
            )
        }
    }
}
