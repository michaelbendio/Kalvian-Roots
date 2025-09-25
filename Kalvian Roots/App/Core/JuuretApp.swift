// JuuretApp.swift - Citation Generation Methods (On-Demand Architecture)
//
// REPLACES the existing generateCitation and generateSpouseCitation methods
// No more citation dictionaries - generate fresh from the network every time!

// MARK: - Citation Generation (On-Demand from Network)

/**
 * Generate citation for any person in the current family
 * NEW ARCHITECTURE: No citation dictionary - generate fresh from network
 *
 * @param person The actual Person object that was clicked
 * @param family The family context where this person appears
 * @return Fresh citation generated from the network
 */
func generateCitation(for person: Person, in family: Family) -> String {
    logInfo(.citation, "📝 Generating on-demand citation for: \(person.displayName)")
    logInfo(.citation, "  Birth date: \(person.birthDate ?? "unknown")")
    logInfo(.citation, "  In family: \(family.familyId)")
    
    // Get the network if available (it should be for enhanced families)
    let network = familyNetworkWorkflow?.getFamilyNetwork()
    
    // Determine the person's role in this family
    let isParent = family.allParents.contains { parent in
        arePersonsEqual(parent, person)
    }
    
    let isChild = family.allChildren.contains { child in
        arePersonsEqual(child, person)
    }
    
    logInfo(.citation, "  Role: \(isParent ? "parent" : isChild ? "child" : "unknown")")
    
    // Generate appropriate citation based on role
    if isParent {
        // Check if this parent has an asChild family in the network
        if let network = network,
           let asChildFamily = network.getAsChildFamily(for: person) {
            logInfo(.citation, "✅ Found parent's asChild family: \(asChildFamily.familyId)")
            
            // Create enhanced network with parent's nuclear family as their asParent
            var enhancedNetwork = network
            // Store the nuclear family as this parent's asParent for enhancement
            enhancedNetwork.asParentFamilies[person.displayName] = family
            enhancedNetwork.asParentFamilies[person.name] = family
            
            // Generate enhanced asChild citation
            return CitationGenerator.generateAsChildCitation(
                for: person,
                in: asChildFamily,
                network: enhancedNetwork,
                nameEquivalenceManager: nameEquivalenceManager
            )
        } else {
            logInfo(.citation, "ℹ️ No asChild family for parent - using main family citation")
            // Fallback to main family citation for parent
            return CitationGenerator.generateMainFamilyCitation(
                family: family,
                targetPerson: nil,  // No arrow for parent without asChild
                network: network
            )
        }
    }
    
    if isChild {
        // For children, always use main family citation with them as target
        // The citation generator will handle enhancement if asParent exists
        logInfo(.citation, "  Generating child citation with potential enhancement")
        return CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: person,  // Arrow points to this child
            network: network       // Network has asParent info if it exists
        )
    }
    
    // Unknown role - shouldn't happen but handle gracefully
    logWarn(.citation, "⚠️ Person role unclear in family context")
    return CitationGenerator.generateMainFamilyCitation(
        family: family,
        targetPerson: nil,
        network: network
    )
}

/**
 * Generate citation for a spouse (children's spouses)
 * NEW ARCHITECTURE: Generate fresh from network
 *
 * @param spousePerson The actual spouse Person object
 * @param childPerson The child who has this spouse
 * @param family The nuclear family context
 * @return Fresh citation for the spouse
 */
func generateSpouseCitation(for spousePerson: Person,
                           marriedTo childPerson: Person,
                           in family: Family) -> String {
    logInfo(.citation, "📝 Generating on-demand spouse citation")
    logInfo(.citation, "  Spouse: \(spousePerson.displayName)")
    logInfo(.citation, "  Married to: \(childPerson.displayName)")
    logInfo(.citation, "  In family: \(family.familyId)")
    
    guard let network = familyNetworkWorkflow?.getFamilyNetwork() else {
        logWarn(.citation, "⚠️ No network available for spouse citation")
        return "Citation unavailable for \(spousePerson.displayName)"
    }
    
    // First, get the child's asParent family (where the spouse appears)
    guard let asParentFamily = network.getAsParentFamily(for: childPerson) else {
        logWarn(.citation, "⚠️ No asParent family found for child")
        return "Citation unavailable for \(spousePerson.displayName)"
    }
    
    logInfo(.citation, "  Found asParent family: \(asParentFamily.familyId)")
    
    // Now check if the spouse has their own asChild family
    if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spousePerson) {
        logInfo(.citation, "✅ Found spouse's asChild family: \(spouseAsChildFamily.familyId)")
        
        // Create enhanced network with spouse's marriage family as their asParent
        var enhancedNetwork = network
        enhancedNetwork.asParentFamilies[spousePerson.displayName] = asParentFamily
        enhancedNetwork.asParentFamilies[spousePerson.name] = asParentFamily
        
        // Generate enhanced asChild citation for spouse
        return CitationGenerator.generateAsChildCitation(
            for: spousePerson,
            in: spouseAsChildFamily,
            network: enhancedNetwork,
            nameEquivalenceManager: nameEquivalenceManager
        )
    } else {
        logInfo(.citation, "ℹ️ No asChild family for spouse - using marriage family citation")
        // Fallback: Generate citation from the marriage (asParent) family
        return CitationGenerator.generateMainFamilyCitation(
            family: asParentFamily,
            targetPerson: spousePerson,
            network: network
        )
    }
}

// MARK: - Helper Methods

/**
 * Check if two Person objects represent the same person
 * Uses birth date as primary identifier, falls back to name
 */
private func arePersonsEqual(_ person1: Person, _ person2: Person) -> Bool {
    // First try birth date (most reliable)
    if let birth1 = person1.birthDate?.trimmingCharacters(in: .whitespaces),
       let birth2 = person2.birthDate?.trimmingCharacters(in: .whitespaces),
       !birth1.isEmpty && !birth2.isEmpty {
        return birth1 == birth2
    }
    
    // Then try display name
    if person1.displayName == person2.displayName {
        return true
    }
    
    // Finally try simple name
    return person1.name.lowercased() == person2.name.lowercased()
}

// MARK: - Manual Citation Override Support (Optional)

/**
 * Check for manual citation override before generating
 * This wrapper can be used if you want to keep manual override support
 */
func getCitationWithOverride(for person: Person, in family: Family) -> String {
    // Check for manual override first
    let overrideKey = "\(family.familyId)|\(person.displayName)"
    if let manualCitation = manualCitations[overrideKey] {
        logInfo(.citation, "📌 Using manual citation override for \(person.displayName)")
        return manualCitation
    }
    
    // Otherwise generate fresh
    return generateCitation(for: person, in: family)
}
