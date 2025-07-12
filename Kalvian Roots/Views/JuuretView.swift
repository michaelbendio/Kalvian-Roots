//
//  JuuretView.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import SwiftUI
import FoundationModels

struct JuuretView: View {
    @Environment(JuuretApp.self) var app
    @State private var familyId = ""
    @State private var isExtracting = false
    @State private var showingCitation = false
    @State private var citationText = ""
    @State private var showingHiskiResult = false
    @State private var hiskiResult = ""
    @State private var showingSpouseCitation = false
    @State private var spouseCitationText = ""
    
    let systemModel = SystemLanguageModel.default
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Foundation Models Availability Check
                availabilityStatusView
                
                // Family Input Section (only show if available)
                if systemModel.availability == .available {
                    inputSection
                    
                    // Extraction Status
                    if isExtracting {
                        extractionStatus
                    }
                    
                    // Family Display
                    if let family = app.currentFamily {
                        Text("✅ Family Loaded: \(family.familyId)")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.bottom, 10)
                        
                        familyDisplaySection(family: family)
                    } else {
                        Text("No family data loaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Family Extraction")
        .alert("Citation", isPresented: $showingCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(citationText)
            }
            Button("OK") { }
        } message: {
            Text(citationText)
        }
        .alert("Hiski Query Result", isPresented: $showingHiskiResult) {
            Button("Copy URL") {
                copyToClipboard(hiskiResult)
            }
            Button("OK") { }
        } message: {
            Text(hiskiResult)
        }
        .alert("Spouse Citation", isPresented: $showingSpouseCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(spouseCitationText)
            }
            Button("OK") { }
        } message: {
            Text(spouseCitationText)
        }
    }
    
    var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Family Extraction")
                .font(.headline)
            
            HStack {
                TextField("Family ID (e.g., Korpi 6)", text: $familyId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        // Handle Enter key press
                        if !familyId.isEmpty && !isExtracting {
                            Task {
                                await extractFamily()
                            }
                        }
                    }
                
                Button("Extract") {
                    Task {
                        await extractFamily()
                    }
                }
                .disabled(familyId.isEmpty || isExtracting)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    func familyDisplaySection(family: Family) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            // Family Header
            VStack(alignment: .leading) {
                Text(family.familyId)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Pages \(family.pageReferences.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Click Instructions
            Text("💡 Click names for citations, dates for Hiski queries, purple spouse names for spouse citations")
                .font(.caption2)
                .foregroundColor(.blue)
                .padding(.vertical, 5)
            
            // Parents Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Parents:")
                    .font(.headline)
                
                // Father - No purple spouse link
                PersonRowView(
                    person: family.father,
                    role: "Father",
                    onNameClick: { person in
                        showCitation(for: person, in: family)
                    },
                    onDateClick: { date, eventType in
                        showHiskiQuery(for: date, eventType: eventType)
                    },
                    onSpouseClick: { spouseName in
                        showSpouseCitation(spouseName: spouseName, in: family)
                    }
                )
                
                // Mother - No purple spouse link
                if let mother = family.mother {
                    PersonRowView(
                        person: mother,
                        role: "Mother",
                        onNameClick: { person in
                            showCitation(for: person, in: family)
                        },
                        onDateClick: { date, eventType in
                            showHiskiQuery(for: date, eventType: eventType)
                        },
                        onSpouseClick: { spouseName in
                            showSpouseCitation(spouseName: spouseName, in: family)
                        }
                    )
                }
                
                // Additional Spouses
                ForEach(Array(family.additionalSpouses.enumerated()), id: \.offset) { _, spouse in
                    PersonRowView(
                        person: spouse,
                        role: "Additional Spouse",
                        onNameClick: { person in
                            showCitation(for: person, in: family)
                        },
                        onDateClick: { date, eventType in
                            showHiskiQuery(for: date, eventType: eventType)
                        },
                        onSpouseClick: { spouseName in
                            showSpouseCitation(spouseName: spouseName, in: family)
                        }
                    )
                }
            }
            
            Divider()
            
            // Children Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Children:")
                    .font(.headline)
                
                ForEach(Array(family.children.enumerated()), id: \.offset) { _, child in
                    PersonRowView(
                        person: child,
                        role: "Child", // This will show purple spouse links
                        onNameClick: { person in
                            showCitation(for: person, in: family)
                        },
                        onDateClick: { date, eventType in
                            showHiskiQuery(for: date, eventType: eventType)
                        },
                        onSpouseClick: { spouseName in
                            showSpouseCitation(spouseName: spouseName, in: family)
                        }
                    )
                }
            }
            
            // Notes Section
            if !family.notes.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Notes:")
                        .font(.headline)
                    
                    ForEach(family.notes, id: \.self) { note in
                        Text("• \(note)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 2)
    }
    
    // Keep all the other functions the same...
    var availabilityStatusView: some View {
        Group {
            switch systemModel.availability {
            case .available:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Foundation Models Ready")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            case .unavailable(.appleIntelligenceNotEnabled):
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Apple Intelligence Not Enabled")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text("Please enable Apple Intelligence in System Settings")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            case .unavailable(.deviceNotEligible):
                VStack {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Device Not Compatible")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Text("This device doesn't support Apple Intelligence")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            case .unavailable(.modelNotReady):
                VStack {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Model Downloading...")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Text("Foundation Models are being prepared")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            case .unavailable(_):
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Foundation Models Unavailable")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    var extractionStatus: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Extracting family data...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    func extractFamily() async {
        print("🚀 extractFamily() called from UI")
        isExtracting = true
        
        do {
            try await app.extractFamily(familyId: familyId.uppercased())
            print("✅ extractFamily() completed successfully")
        } catch {
            print("❌ Extraction error: \(error)")
        }
        
        isExtracting = false
        print("🏁 isExtracting set to false")
    }
    
    func showCitation(for person: Person, in family: Family) {
        print("📄 Show citation for: \(person.displayName)")
        citationText = app.generateCitation(for: person, in: family)
        showingCitation = true
    }
    
    func showHiskiQuery(for date: String, eventType: EventType) {
        print("🔍 Show Hiski query for: \(date)")
        hiskiResult = app.generateHiskiQuery(for: date, eventType: eventType)
        showingHiskiResult = true
    }
    
    func showSpouseCitation(spouseName: String, in family: Family) {
        print("💑 Show spouse citation for: \(spouseName)")
        spouseCitationText = app.generateSpouseCitation(spouseName: spouseName, in: family)
        showingSpouseCitation = true
    }
    
    func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        print("📋 Copied to clipboard: \(text.prefix(50))...")
    }
}
