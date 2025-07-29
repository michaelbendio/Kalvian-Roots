//
//  JuuretView.swift - UPDATED with MLX Support and Enhanced Fonts
//  Kalvian Roots
//
//  Enhanced genealogical interface with larger fonts and MLX integration
//

import SwiftUI

struct JuuretView: View {
    @Environment(JuuretApp.self) private var juuretApp
    @State private var familyId = ""
    @State private var showingCitation = false
    @State private var citationText = ""
    @State private var showingHiskiResult = false
    @State private var hiskiResult = ""
    @State private var showingSpouseCitation = false
    @State private var spouseCitationText = ""
    
    var body: some View {
        VStack(spacing: 25) { // Increased spacing
            if juuretApp.fileManager.isFileLoaded {
                familyExtractionInterface
            } else {
                fileNotLoadedInterface
            }
        }
        .padding(20) // Increased padding
        .navigationTitle("Kalvian Roots")
        .alert("Citation", isPresented: $showingCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(citationText)
            }
            Button("OK") { }
        } message: {
            Text(citationText)
                .font(.genealogyCallout) // Enhanced font
        }
        .alert("Hiski Query Result", isPresented: $showingHiskiResult) {
            Button("Copy URL") {
                copyToClipboard(hiskiResult)
            }
            Button("OK") { }
        } message: {
            Text(hiskiResult)
                .font(.genealogyCallout) // Enhanced font
        }
        .alert("Spouse Citation", isPresented: $showingSpouseCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(spouseCitationText)
            }
            Button("OK") { }
        } message: {
            Text(spouseCitationText)
                .font(.genealogyCallout) // Enhanced font
        }
        .onAppear {
            logInfo(.ui, "JuuretView appeared (Enhanced version)")
        }
    }
    
    // MARK: - Family Extraction Interface (Enhanced)
    
    private var familyExtractionInterface: some View {
        VStack(spacing: 25) { // Increased spacing
            // Enhanced header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.genealogySubheadline) // Larger icon
                Text("Ready")
                    .foregroundColor(.green)
                    .font(.genealogySubheadline) // Enhanced font
                Spacer()
                if let url = juuretApp.fileManager.currentFileURL {
                    Text(url.lastPathComponent)
                        .font(.genealogyCallout) // Enhanced font
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            
            // Enhanced family ID input
            VStack(alignment: .leading, spacing: 15) { // Increased spacing
                Text("Family ID?")
                    .font(.genealogyTitle2) // Much larger title
                    .fontWeight(.medium)
                
                HStack(spacing: 15) { // Increased spacing
                    TextField("e.g., Korpi 6", text: $familyId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.genealogyBody) // Enhanced font
                        .frame(height: 40) // Taller text field
                        .onSubmit {
                            if !familyId.isEmpty && !juuretApp.isProcessing {
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
                    .disabled(familyId.isEmpty || juuretApp.isProcessing)
                    .buttonStyle(.borderedProminent)
                    .font(.genealogySubheadline) // Enhanced font
                    .frame(height: 40) // Taller button
                    
                    Button("Complete") {
                        Task {
                            await extractFamilyComplete()
                        }
                    }
                    .disabled(familyId.isEmpty || juuretApp.isProcessing)
                    .buttonStyle(.bordered)
                    .font(.genealogySubheadline) // Enhanced font
                    .frame(height: 40) // Taller button
                    .help("Extract family + resolve cross-references")
                }
            }
            .padding(20) // Increased padding
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12) // Slightly larger corner radius
            
            // Enhanced MLX model selection (macOS only)
            #if os(macOS)
            if MLXService.isAvailable() {
                mlxModelSelectionView
            }
            #endif
            
            // Enhanced processing status
            if juuretApp.isProcessing {
                enhancedProcessingStatusView
            }
            
            // Enhanced error display
            if let errorMessage = juuretApp.errorMessage, !juuretApp.isProcessing {
                enhancedErrorDisplayView(errorMessage)
            }
            
            // Enhanced family display
            if let family = juuretApp.currentFamily {
                enhancedFamilyDisplaySection(family: family)
            }
            
            Spacer()
        }
    }
    
    // MARK: - MLX Model Selection (macOS Only)
    
    #if os(macOS)
    private var mlxModelSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.blue)
                    .font(.genealogySubheadline)
                Text("Local AI Models")
                    .font(.genealogyHeadline)
                    .fontWeight(.medium)
                Spacer()
                Text("🖥️ Apple Silicon")
                    .font(.genealogyCaption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                Button("Mistral-7B (Fast)") {
                    Task {
                        try? await juuretApp.switchAIService(to: "Mistral-7B (Local MLX)")
                    }
                }
                .buttonStyle(.bordered)
                .font(.genealogyCallout)
                .controlSize(.small)
                
                Button("Llama3.2-8B (Balanced)") {
                    Task {
                        try? await juuretApp.switchAIService(to: "Llama3.2-8B (Local MLX)")
                    }
                }
                .buttonStyle(.bordered)
                .font(.genealogyCallout)
                .controlSize(.small)
                
                Button("Qwen3-30B (Best)") {
                    Task {
                        try? await juuretApp.switchAIService(to: "Qwen3-30B (Local MLX)")
                    }
                }
                .buttonStyle(.bordered)
                .font(.genealogyCallout)
                .controlSize(.small)
                
                Spacer()
            }
            
            Text("Current: \(juuretApp.currentServiceName)")
                .font(.genealogyCaption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }
    #endif
    
    // MARK: - Enhanced Status Views
    
    private var enhancedProcessingStatusView: some View {
        HStack(spacing: 15) {
            ProgressView()
                .scaleEffect(1.0) // Larger progress indicator
            Text(juuretApp.extractionProgress.description)
                .font(.genealogySubheadline) // Enhanced font
                .foregroundColor(.secondary)
        }
        .padding(20) // Increased padding
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func enhancedErrorDisplayView(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 15) { // Increased spacing
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.genealogySubheadline) // Larger icon
                Text("Error")
                    .font(.genealogyHeadline) // Enhanced font
                    .foregroundColor(.red)
            }
            
            Text(errorMessage)
                .font(.genealogyBody) // Enhanced font
                .foregroundColor(.primary)
                .padding(16) // Increased padding
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
        }
        .padding(20) // Increased padding
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - File Not Loaded Interface (Enhanced)
    
    private var fileNotLoadedInterface: some View {
        VStack(spacing: 25) { // Increased spacing
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.orange)
                    .font(.genealogySubheadline) // Larger icon
                Text("No file loaded")
                    .foregroundColor(.orange)
                    .font(.genealogySubheadline) // Enhanced font
                Spacer()
                Button("Open File...") {
                    logInfo(.ui, "User manually opening file")
                    Task {
                        do {
                            let content = try await juuretApp.fileManager.openFile()
                            juuretApp.updateFileContent()
                            logInfo(.ui, "✅ File manually opened successfully")
                        } catch FileManagerError.userCancelled {
                            logInfo(.ui, "User cancelled file selection")
                        } catch {
                            logError(.ui, "❌ Failed to manually open file: \(error)")
                            juuretApp.errorMessage = "Failed to open file: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .font(.genealogySubheadline) // Enhanced font
                .frame(height: 40) // Taller button
            }
            .padding(20) // Increased padding
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
        }
    }
    
    // MARK: - Enhanced Family Display
    
    private func enhancedFamilyDisplaySection(family: Family) -> some View {
        VStack(alignment: .leading, spacing: 20) { // Increased spacing
            // Enhanced family header
            VStack(alignment: .leading, spacing: 8) {
                Text(family.familyId)
                    .font(.genealogyTitle) // Much larger title
                    .fontWeight(.bold)
                Text("Pages \(family.pageReferences.joined(separator: ", "))")
                    .font(.genealogyCallout) // Enhanced font
                    .foregroundColor(.secondary)
            }
            
            // Enhanced click instructions
            Text("💡 Click names for citations, dates for Hiski queries, purple spouse names for spouse citations")
                .font(.genealogyCallout) // Enhanced font
                .foregroundColor(.blue)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            // Enhanced parents section
            VStack(alignment: .leading, spacing: 15) { // Increased spacing
                Text("Parents:")
                    .font(.genealogyHeadline) // Enhanced font
                
                // Father
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
                
                // Mother
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
                
                // Additional spouses
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
                .padding(.vertical, 5)
            
            // Enhanced children section
            VStack(alignment: .leading, spacing: 15) { // Increased spacing
                Text("Children:")
                    .font(.genealogyHeadline) // Enhanced font
                
                ForEach(Array(family.children.enumerated()), id: \.offset) { _, child in
                    PersonRowView(
                        person: child,
                        role: "Child",
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
            
            // Enhanced notes section
            if !family.notes.isEmpty {
                Divider()
                    .padding(.vertical, 5)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notes:")
                        .font(.genealogyHeadline) // Enhanced font
                    
                    ForEach(family.notes, id: \.self) { note in
                        Text("• \(note)")
                            .font(.genealogyCallout) // Enhanced font
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Enhanced child mortality info
            if let childrenDied = family.childrenDiedInfancy {
                Text("Children died in infancy: \(childrenDied)")
                    .font(.genealogyCallout) // Enhanced font
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(20) // Increased padding
        .background(Color.white)
        .cornerRadius(12) // Larger corner radius
        .shadow(radius: 3) // Slightly larger shadow
    }
    
    // MARK: - Action Methods (Enhanced)
    
    private func extractFamily() async {
        logInfo(.ui, "User initiated family extraction: \(familyId)")
        
        do {
            try await juuretApp.extractFamily(familyId: familyId.uppercased())
            logInfo(.ui, "Family extraction completed successfully")
        } catch {
            logError(.ui, "Family extraction failed: \(error)")
        }
    }
    
    private func extractFamilyComplete() async {
        logInfo(.ui, "User initiated complete family extraction with cross-references: \(familyId)")
        
        do {
            try await juuretApp.extractFamilyComplete(familyId: familyId.uppercased())
            logInfo(.ui, "Complete family extraction completed successfully")
        } catch {
            logError(.ui, "Complete family extraction failed: \(error)")
        }
    }
    
    private func showCitation(for person: Person, in family: Family) {
        logInfo(.ui, "User requested citation for: \(person.displayName)")
        citationText = juuretApp.generateCitation(for: person, in: family)
        showingCitation = true
        logDebug(.citation, "Generated citation length: \(citationText.count) characters")
    }
    
    private func showHiskiQuery(for date: String, eventType: EventType) {
        logInfo(.ui, "User requested Hiski query for: \(date) (\(eventType))")
        hiskiResult = juuretApp.generateHiskiQuery(for: date, eventType: eventType)
        showingHiskiResult = true
        logDebug(.citation, "Generated Hiski URL: \(hiskiResult)")
    }
    
    private func showSpouseCitation(spouseName: String, in family: Family) {
        logInfo(.ui, "User requested spouse citation for: \(spouseName)")
        spouseCitationText = juuretApp.generateSpouseCitation(spouseName: spouseName, in: family)
        showingSpouseCitation = true
        logDebug(.citation, "Generated spouse citation length: \(spouseCitationText.count) characters")
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        logInfo(.ui, "Copied to clipboard: \(text.prefix(50))...")
    }
}
