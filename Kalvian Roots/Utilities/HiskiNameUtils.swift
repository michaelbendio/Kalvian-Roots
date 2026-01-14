//
//  HiskiNameUtils.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 3/6/25
//

import Foundation

enum Gender {
    case male
    case female
    case unknown
}

class HiskiNameUtils {
    // Male name variants
    private let maleNameVariants: [String: Set<String>] = [
        "aabraham": ["abram", "abraham", "abrahammus"],
        "aaron": ["aron", "aaron"],
        "antti": ["anders", "andreas", "andrej"],
        "david": ["dawid", "taavetti"],
        "eerik": ["erik", "eric", "erich"],
        "elias": ["elijs", "elis"],
        "gabriel": ["gabril"],
        "gustaf": ["kustaa", "kusataa", "gustav", "gustav"],
        "henrik": ["henrik", "hendrich", "heikki"],
        "jaakko": ["jacob", "jakob", "jacobus", "jaako", "jacop"],
        "jean": ["johan", "johannes", "johanne", "juho", "jöns", "hans"],
        "juho": ["johan", "johannes", "johann"],
        "kalle": ["carl", "karl"],
        "kristian": ["christian", "kristian"],
        "lauri": ["lars", "laurentius", "laurent"],
        "markus": ["marcus", "marx"],
        "martti": ["martin", "martinus", "mårten"],
        "matias": ["mathias", "matthias", "mats", "matts", "matti", "matin"],
        "mikael": ["mickel", "michel", "mikko"],
        "niilo": ["nicolaus", "nils", "niklas"],
        "olavi": ["olof", "olaus", "ole"],
        "paavali": ["paul", "pauli", "påhl", "pål"],
        "petteri": ["petter", "peter", "pietari", "petrus"],
        "sakari": ["sakarias", "zacharias"],
        "simo": ["simon", "simen"],
        "tuomas": ["thomas", "tomas"],
    ]

    // Female name variants
    private let femaleNameVariants: [String: Set<String>] = [
        "agneta": ["agneta", "agnete", "aune"],
        "anna": ["anna", "anne", "arna", "annika"],
        "brita": ["briita", "brigitta", "brit", "bridget"],
        "catharina": ["katariina", "kaarin", "kaarina", "katarina", "carin", "karin"],
        "elisabet": ["elisabet", "elisabeth", "lisa", "liisa", "betta", "elisabeta"],
        "elin": ["elena", "elina", "helen"],
        "eva": ["eeva"],
        "greta": ["kreta", "kreeta", "margareta", "margeta", "magareta", "margaretha"],
        "helena": ["helena", "helga", "elena"],
        "johanna": ["johana"],
        "kristina": ["kristiina", "christina", "stiina", "stina", "christina"],
        "liisa": ["elisabet", "lisa", "elisabeth"],
        "magdalena": ["magdaleena", "malin", "malen", "malena"],
        "maria": ["maria", "marie", "marja"],
        "sofia": ["sofia", "sophie"],
        "susanna": ["susana", "susanne"],
    ]

    private let patronymicSuffixes: Set<String> = [
        "p.", "poika", "son", "sson",
    ]

    private let feminineSuffixes: Set<String> = [
        "tytär", "dotter", "t.", "dtr",
    ]

    private let titlesToIgnore = Set([
        "bson", "bdot", "bdtr", "torp", "pig", "dr", "son", "sson",
        "bondeson", "torpare", "piga", "dotter", "dräng", "husb", "husbonde",
    ])

    // MARK: - Name Matching
    
    /// Check if two names match, handling Finnish/Swedish variants
    // In HiskiNameUtils.swift
    func namesMatch(_ name1: String, _ name2: String) -> Bool {
        print("DEBUG - Comparing names: '\(name1)' vs '\(name2)'")
        
        let name1Lower = name1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let name2Lower = name2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Direct match
        if name1Lower == name2Lower {
            print("DEBUG - Direct name match")
            return true
        }
        
        // Explicit matches for common issues
        if (name1Lower == "antti" && (name2Lower == "andreas" || name2Lower == "anders")) ||
           (name2Lower == "antti" && (name1Lower == "andreas" || name1Lower == "anders")) {
            print("DEBUG - Explicit match for Antti/Andreas/Anders")
            return true
        }
        
        // Split names to get first name only
        let name1First = name1Lower.split(separator: " ").first.map(String.init) ?? name1Lower
        let name2First = name2Lower.split(separator: " ").first.map(String.init) ?? name2Lower
        
        print("DEBUG - Comparing first names: '\(name1First)' vs '\(name2First)'")
        
        // Check exact matches for Matti/Matts variations
        if (name1First == "matti" && name2First == "matts") ||
           (name1First == "matts" && name2First == "matti") {
            print("DEBUG - Match for Matti/Matts variation")
            return true
        }
        
        // Check given names match using regular variants
        let result = givenNamesMatch(name1First, name2First)
        print("DEBUG - Name matching result: \(result)")
        return result
    }
    
    /// Check if two given names match based on Finnish/Swedish variants
    private func givenNamesMatch(_ name1: String, _ name2: String) -> Bool {
        // Check male names
        for (base, variants) in maleNameVariants {
            if (base == name1 && variants.contains(name2)) ||
               (base == name2 && variants.contains(name1)) ||
               (variants.contains(name1) && variants.contains(name2)) {
                return true
            }
        }
        
        // Check female names
        for (base, variants) in femaleNameVariants {
            if (base == name1 && variants.contains(name2)) ||
               (base == name2 && variants.contains(name1)) ||
               (variants.contains(name1) && variants.contains(name2)) {
                return true
            }
        }
        
        return false
    }
    
    /// Determine gender based on name patterns
    func determineGender(for fullName: String) -> Gender {
        let lowercaseName = fullName.lowercased()
        
        // Check for feminine suffixes
        for suffix in feminineSuffixes {
            if lowercaseName.contains(suffix) {
                return .female
            }
        }
        
        // Check for masculine suffixes
        for suffix in patronymicSuffixes {
            if lowercaseName.contains(suffix) {
                return .male
            }
        }
        
        // Check if the name contains a male or female name
        if let firstName = fullName.split(separator: " ").first?.lowercased() {
            // Check against male names
            for (baseName, variants) in maleNameVariants {
                if baseName == firstName || variants.contains(firstName) {
                    return .male
                }
            }
            
            // Check against female names
            for (baseName, variants) in femaleNameVariants {
                if baseName == firstName || variants.contains(firstName) {
                    return .female
                }
            }
        }
        
        return .unknown
    }
    
    /// Calculate age in years between two dates
    func calculateAgeInYears(birth: Date, death: Date) -> Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birth, to: death)
        return ageComponents.year ?? 0
    }
    
    /// Clean a name for comparison
    func cleanName(_ name: String) -> String {
        return name.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !titlesToIgnore.contains($0.lowercased()) }
            .joined(separator: " ")
    }
}
