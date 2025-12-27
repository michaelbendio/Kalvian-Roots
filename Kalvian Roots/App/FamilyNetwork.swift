//
//  FamilyNetwork.swift
//  Kalvian Roots
//
//  Family network for citation generation with non-recursive resolution
//
//  Created by Michael Bendio on 8/26/25.
//

import Foundation

/**
 * Complete family network supporting citation generation
 *
 * Citation Architecture:
 * - One shared nuclear family citation for parents and children
 * - Each married child gets nuclear citation + their death/marriage dates from asParent family
 * - Parents get citations from their asChild families (non-recursive)
 * - Spouses get citations from their asChild families (non-recursive)
 * - asChild families do NOT recursively follow their own parent/sibling references
 */
struct FamilyNetwork: Hashable, Sendable, Codable {
    /// The main nuclear family that was initially parsed
    let mainFamily: Family
    
    /// Resolved families where mainFamily parents came from (parent.displayName -> their asChild family)
    /// These are NON-RECURSIVE - we don't follow references within these families
    /// Updated to use displayName as primary key to avoid name collisions
    var asChildFamilies: [String: Family] = [:]
    
    /// Resolved families where mainFamily children are parents (child.displayName -> their asParent family)
    /// Updated to use displayName as primary key to avoid name collisions
    var asParentFamilies: [String: Family] = [:]
    
    /// Resolved families where spouses came from (spouse.displayName -> their asChild family)
    /// These are NON-RECURSIVE - we don't follow references within these families
    /// Updated to use displayName as primary key to avoid name collisions
    var spouseAsChildFamilies: [String: Family] = [:]
    
    init(mainFamily: Family) {
        self.mainFamily = mainFamily
    }
    
    // MARK: - Key Generation

    /// Create a unique key for a person using birth date when available
    /// Format: "name|birthDate" or just "name" if no birth date
    static func makePersonKey(name: String, birthDate: String?) -> String {
        if let birthDate = birthDate?.trimmingCharacters(in: .whitespaces), !birthDate.isEmpty {
            return "\(name)|\(birthDate)"
        }
        return name
    }

    /// Create a unique key from a Person object
    static func makePersonKey(for person: Person) -> String {
        return makePersonKey(name: person.name, birthDate: person.birthDate)
    }
    
    // MARK: - Computed Properties for Citation Support
    
    /// Total count of all resolved families for debugging
    var totalResolvedFamilies: Int {
        return 1 + asChildFamilies.count + asParentFamilies.count + spouseAsChildFamilies.count
    }
    
    // MARK: - Citation Helper Methods
    
    /// Get the asParent family for a specific child (where child became a parent)
    func getAsParentFamily(for person: Person) -> Family? {
        // PRIMARY: Try birth date key first (most unique, avoids name collisions)
        if let birthDate = person.birthDate?.trimmingCharacters(in: .whitespaces), !birthDate.isEmpty {
            let birthKey = "\(person.name)|\(birthDate)"
            if let family = asParentFamilies[birthKey] {
                logDebug(.citation, "✅ Found asParent family for '\(person.displayName)' using birth date key '\(birthKey)'")
                return family
            }
        }
        
        // PRIMARY: Try displayName first (most specific)
        if let family = asParentFamilies[person.displayName] {
            logDebug(.citation, "✅ Found asParent family for '\(person.displayName)' using displayName")
            return family
        }
        
        // FALLBACK 1: Try simple name
        if let family = asParentFamilies[person.name] {
            logDebug(.citation, "✅ Found asParent family for '\(person.displayName)' using simple name")
            return family
        }
        
        // FALLBACK 2: Try trimmed version
        let trimmedName = person.name.trimmingCharacters(in: .whitespaces)
        if let family = asParentFamilies[trimmedName] {
            logDebug(.citation, "✅ Found asParent family for '\(person.displayName)' using trimmed name")
            return family
        }
        
        // FALLBACK 3: Try case-insensitive match on displayName
        for (key, family) in asParentFamilies {
            if key.lowercased() == person.displayName.lowercased() {
                logDebug(.citation, "✅ Found asParent family for '\(person.displayName)' using case-insensitive displayName")
                return family
            }
        }
        
        // FALLBACK 4: Try case-insensitive match on simple name
        for (key, family) in asParentFamilies {
            if key.lowercased() == person.name.lowercased() {
                logDebug(.citation, "✅ Found asParent family for '\(person.displayName)' using case-insensitive simple name")
                return family
            }
        }
        
        // FALLBACK 5: try extracting just the first name if searching for a compound name
        let searchTermWords = person.displayName.components(separatedBy: " ")
        if searchTermWords.count > 1, let firstName = searchTermWords.first {
            for (key, family) in asParentFamilies {
                if key.lowercased() == firstName.lowercased() {
                    logDebug(.citation, "✅ Found asParent family for '\(person.displayName)' using first-name extraction from compound name")
                    return family
                }
            }
        }

        // Do the same for person.name if it's different from displayName
        let nameWords = person.name.components(separatedBy: " ")
        if nameWords.count > 1, let firstName = nameWords.first {
            for (key, family) in asParentFamilies {
                if key.lowercased() == firstName.lowercased() {
                    logDebug(.citation, "✅ Found asParent family for '\(person.name)' using first-name extraction")
                    return family
                }
            }
        }
        
        logWarn(.citation, "⚠️ No asParent family found for '\(person.displayName)' in keys: \(Array(asParentFamilies.keys))")
        return nil
    }
    
    func getAsChildFamily(for person: Person) -> Family? {
        // PRIMARY: Try displayName first (most specific)
        if let family = asChildFamilies[person.displayName] {
            logDebug(.citation, "✅ Found asChild family for '\(person.displayName)' using displayName")
            return family
        }
        
        // FALLBACK 1: Try simple name
        if let family = asChildFamilies[person.name] {
            logDebug(.citation, "✅ Found asChild family for '\(person.displayName)' using simple name")
            return family
        }
        
        // FALLBACK 2: Try trimmed version
        let trimmedName = person.name.trimmingCharacters(in: .whitespaces)
        if let family = asChildFamilies[trimmedName] {
            logDebug(.citation, "✅ Found asChild family for '\(person.displayName)' using trimmed name")
            return family
        }
        
        // FALLBACK 3: Try case-insensitive match on displayName
        for (key, family) in asChildFamilies {
            if key.lowercased() == person.displayName.lowercased() {
                logDebug(.citation, "✅ Found asChild family for '\(person.displayName)' using case-insensitive displayName")
                return family
            }
        }
        
        // FALLBACK 4: Try case-insensitive match on simple name
        for (key, family) in asChildFamilies {
            if key.lowercased() == person.name.lowercased() {
                logDebug(.citation, "✅ Found asChild family for '\(person.displayName)' using case-insensitive simple name")
                return family
            }
        }
        
        // Log failure for debugging
        logWarn(.citation, "⚠️ No asChild family found for '\(person.displayName)' in keys: \(Array(asChildFamilies.keys))")
        return nil
    }
    
    /// Get the asChild family for a specific spouse (where spouse came from)
    /// Updated to accept Person object for consistent displayName handling
    func getSpouseAsChildFamily(for spouse: Person) -> Family? {
        // PRIMARY: Try displayName first (most specific)
        if let family = spouseAsChildFamilies[spouse.displayName] {
            logDebug(.citation, "✅ Found spouse asChild family for '\(spouse.displayName)' using displayName")
            return family
        }
        
        // FALLBACK 1: Try simple name
        if let family = spouseAsChildFamilies[spouse.name] {
            logDebug(.citation, "✅ Found spouse asChild family for '\(spouse.displayName)' using simple name")
            return family
        }
        
        // FALLBACK 2: Try trimmed version
        let trimmedName = spouse.name.trimmingCharacters(in: .whitespaces)
        if let family = spouseAsChildFamilies[trimmedName] {
            logDebug(.citation, "✅ Found spouse asChild family for '\(spouse.displayName)' using trimmed name")
            return family
        }
        
        // FALLBACK 3: Try case-insensitive match on displayName
        for (key, family) in spouseAsChildFamilies {
            if key.lowercased() == spouse.displayName.lowercased() {
                logDebug(.citation, "✅ Found spouse asChild family for '\(spouse.displayName)' using case-insensitive displayName")
                return family
            }
        }
        
        // FALLBACK 4: Try case-insensitive match on simple name
        for (key, family) in spouseAsChildFamilies {
            if key.lowercased() == spouse.name.lowercased() {
                logDebug(.citation, "✅ Found spouse asChild family for '\(spouse.displayName)' using case-insensitive simple name")
                return family
            }
        }
        
        // FALLBACK 5: Extract first name from compound names
        let searchWords = spouse.name.components(separatedBy: " ")
        if searchWords.count > 1, let firstName = searchWords.first {
            for (key, family) in spouseAsChildFamilies {
                // Check if the key starts with the first name
                if key.lowercased().hasPrefix(firstName.lowercased()) {
                    logDebug(.citation, "✅ Found spouse asChild family for '\(spouse.name)' using first-name prefix match")
                    return family
                }
            }
        }
        
        // Log failure for debugging
        logWarn(.citation, "⚠️ No spouse asChild family found for '\(spouse.displayName)' in keys: \(Array(spouseAsChildFamilies.keys))")
        return nil
    }
    
    /// Overloaded method for backwards compatibility with string parameter
    func getSpouseAsChildFamily(for spouseName: String) -> Family? {
        // Create a temporary Person object with the spouse name
        let tempSpouse = Person(name: spouseName, noteMarkers: [])
        return getSpouseAsChildFamily(for: tempSpouse)
    }
    
    /// Get all families in the network (for comprehensive citation generation)
    var allFamilies: [Family] {
        var families = [mainFamily]
        families.append(contentsOf: asChildFamilies.values)
        families.append(contentsOf: asParentFamilies.values)
        families.append(contentsOf: spouseAsChildFamilies.values)
        return families
    }
    
    // MARK: - Debug Information
    
    var debugSummary: String {
        return """
        FamilyNetwork Summary:
        - Main Family: \(mainFamily.familyId)
        - AsChild Families: \(asChildFamilies.count)
        - AsParent Families: \(asParentFamilies.count) 
        - Spouse AsChild Families: \(spouseAsChildFamilies.count)
        - Total Resolved: \(totalResolvedFamilies)
        """
    }
}
