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
    
    /// Resolved families where mainFamily parents came from (parent.name -> their asChild family)
    /// These are NON-RECURSIVE - we don't follow references within these families
    var asChildFamilies: [String: Family] = [:]
    
    /// Resolved families where mainFamily children are parents (child.name -> their asParent family)
    var asParentFamilies: [String: Family] = [:]
    
    /// Resolved families where spouses came from (spouse.name -> their asChild family)
    /// These are NON-RECURSIVE - we don't follow references within these families
    var spouseAsChildFamilies: [String: Family] = [:]
    
    init(mainFamily: Family) {
        self.mainFamily = mainFamily
    }
    
    // MARK: - Computed Properties for Citation Support
    
    /// Total count of all resolved families for debugging
    var totalResolvedFamilies: Int {
        return 1 + asChildFamilies.count + asParentFamilies.count + spouseAsChildFamilies.count
    }
    
    // MARK: - Citation Helper Methods
    
    /// Get the asParent family for a specific child (where child became a parent)
    func getAsParentFamily(for person: Person) -> Family? {
        return asParentFamilies[person.name]
    }
    
    /// Get the asChild family for a specific parent (where parent came from)
    func getAsChildFamily(for person: Person) -> Family? {
        return asChildFamilies[person.name]
    }
    
    /// Get the asChild family for a specific spouse (where spouse came from)
    func getSpouseAsChildFamily(for spouseName: String) -> Family? {
        return spouseAsChildFamilies[spouseName]
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
