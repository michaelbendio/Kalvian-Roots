/**
 * FinalGenerableTest.swift
 *
 * FINAL TEST: The discovered @Generable pattern from WWDC code snippets
 *
 * Based on research finding: session.respond(to: "prompt", generating: Type.self)
 */

import Foundation
import FoundationModels

/**
 * Test @Generable struct with @Guide descriptions
 */
@Generable
struct TestFamily: Hashable, Sendable {
    @Guide(description: "A unique family identifier like 'KORPI 6' or 'TEST 1'")
    var familyId: String
    
    @Guide(description: "The father's given name and patronymic")
    var fatherName: String
    
    @Guide(description: "The mother's given name and patronymic, may be nil")
    var motherName: String?
    
    @Guide(description: "The number of children in the family")
    var childrenCount: Int
}

/**
 * THE FINAL TEST - Pattern E from WWDC
 */
func testGenerablePatternE() async {
    print("🧪 FINAL @Generable Test - Pattern E")
    print("===================================")
    
    // Check availability first
    let systemModel = SystemLanguageModel.default
    print("Model availability: \(systemModel.availability)")
    
    guard case .available = systemModel.availability else {
        print("❌ Foundation Models not available")
        return
    }
    
    print("✅ Foundation Models available")
    
    // THE MOMENT OF TRUTH - Pattern E from WWDC code snippets
    do {
        let session = LanguageModelSession()
        print("✅ Session created")
        
        print("Testing the WWDC pattern: session.respond(to:, generating:)")
        
        let response = try await session.respond(
            to: "Generate a family with familyId 'TEST', fatherName 'John', motherName 'Jane', childrenCount 2",
            generating: TestFamily.self
        )
        
        print("🎉🎉🎉 SUCCESS! @Generable works with 'generating:' parameter!")
        print("Response type: \(type(of: response))")
        print("Content type: \(type(of: response.content))")
        print("Generated family: \(response.content)")
        print("Family ID: \(response.content.familyId)")
        print("Father: \(response.content.fatherName)")
        print("Mother: \(response.content.motherName ?? "nil")")
        print("Children: \(response.content.childrenCount)")
        
    } catch {
        print("❌ Pattern E failed: \(error)")
        print("Error type: \(type(of: error))")
        print("Error details: \(error.localizedDescription)")
    }
    
    print("\n🎯 TEST COMPLETE!")
}

/**
 * SwiftUI View to run the test
 */
import SwiftUI

struct FinalGenerableTestView: View {
    @State private var isTestingInProgress = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Final @Generable Test")
                .font(.title)
                .bold()
            
            Text("Testing: session.respond(to:, generating:)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("🚀 Test Pattern E") {
                isTestingInProgress = true
                Task {
                    await testGenerablePatternE()
                    isTestingInProgress = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTestingInProgress)
            
            if isTestingInProgress {
                ProgressView("Testing @Generable...")
            }
            
            Text("Check Xcode Console for results")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
