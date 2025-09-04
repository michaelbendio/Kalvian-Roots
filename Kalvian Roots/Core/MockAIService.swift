//
//  MockAIService.swift
//  Kalvian Roots
//
//  Simple mock AI service used as a safe fallback when real services are unavailable.
//

import Foundation

class MockAIService: AIService {
    let name = "Mock AI"
    
    var isConfigured: Bool {
        // Always "configured" so the app can function without API keys
        true
    }
    
    func configure(apiKey: String) throws {
        // No-op for mock
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🧪 MockAIService returning deterministic mock JSON for \(familyId)")
        
        // Provide JSON in the modern "couples" structure expected by AIParsingService
        return """
        {
          "familyId": "\(familyId)",
          "pageReferences": ["999"],
          "couples": [
            {
              "husband": {
                "name": "Mock Father",
                "patronymic": "Mockp.",
                "birthDate": "01.01.1700",
                "deathDate": null,
                "asChild": null,
                "familySearchId": null
              },
              "wife": {
                "name": "Mock Mother",
                "patronymic": "Mockt.",
                "birthDate": "01.01.1705",
                "deathDate": null,
                "asChild": null,
                "familySearchId": null
              },
              "marriageDate": "1724",
              "fullMarriageDate": null,
              "children": [
                {
                  "name": "Mock Child",
                  "birthDate": "01.01.1730",
                  "deathDate": null,
                  "marriageDate": null,
                  "spouse": null,
                  "asParent": null,
                  "familySearchId": null
                }
              ],
              "childrenDiedInfancy": 0,
              "coupleNotes": []
            }
          ],
          "notes": ["MOCK RESPONSE - No real AI call performed"],
          "noteDefinitions": {},
          "childrenDiedInfancy": null
        }
        """
    }
}

#if canImport(OSLog)
import OSLog
private func logInfo(_ category: OSLog, _ message: String) {
    os_log("%{public}@", log: category, type: .info, message)
}
#else
private func logInfo(_ category: Any, _ message: String) {
    print("[INFO] \(message)")
}
#endif
