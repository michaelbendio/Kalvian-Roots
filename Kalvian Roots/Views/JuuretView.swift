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
        VStack(spacing: 20) { // Increased spacing
            #if os(macOS)
            mlxSwitchingInterface
            #endif
            
            if juuretApp.isProcessing {
                enhancedProcessingStatusView
            } else if let errorMessage = juuretApp.errorMessage {
                enhancedErrorDisplayView(errorMessage)
            } else if let family = juuretApp.currentFamily {
                enhancedFamilyDisplaySection(family: family)
            } else {
                enhancedFamilyInputSection
            }
        }
    }
    
    private var enhancedFamilyInputSection: some View {
        VStack(spacing: 20) { // Increased spacing
            Text("Extract Family")
                .font(.genealogyTitle) // Much larger title
                .fontWeight(.bold)
            
            VStack(spacing: 15) { // Increased spacing
                TextField("Family ID (e.g., KORPI 6)", text: $familyId)
                    .textFieldStyle(.roundedBorder)
                    .font(.genealogySubheadline) // Enhanced font
                    .frame(height: 40) // Taller text field
                
                HStack(spacing: 15) { // Increased spacing
                    Button("Extract Basic") {
                        Task { await extractFamily() }
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.genealogySubheadline) // Enhanced font
                    .frame(height: 40) // Taller button
                    
                    Button("Extract Complete") {
                        Task { await extractFamilyComplete() }
                    }
                    .buttonStyle(.bordered)
                    .font(.genealogySubheadline) // Enhanced font
                    .frame(height: 40) // Taller button
                }
            }
            .padding(20) // Increased padding
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    #if os(macOS)
    // MARK: - MLX Switching Interface (Enhanced for macOS only)
    
    private var mlxSwitchingInterface: some View {
        VStack(spacing: 12) { // Increased spacing
            Text("AI Service (Local MLX Available)")
                .font(.genealogyHeadline) // Enhanced font
                .fontWeight(.semibold)
            
            HStack(spacing: 10) {
                Button("DeepSeek") {
                    Task {
                        do {
                            try await juuretApp.switchAIService(to: "DeepSeek")
                        } catch {
                            logError(.ui, "Failed to switch AI Service: \(error)")
                            juuretApp.errorMessage = "Failed to switch AI Service: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.genealogyCallout)
                .controlSize(.small)
                
                Button("Qwen3-30B (Best)") {
                    Task {
                        do {
                            try await juuretApp.switchAIService(to: "MLX Qwen3-30B (Local)")
                        } catch {
                            logError(.ui, "Failed to switch AI Service: \(error)")
                            juuretApp.errorMessage = "Failed to switch AI Service: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.genealogyCallout)
                .controlSize(.small)
                
                Button("Llama3.2-8B") {
                    Task {
                        do {
                            try await juuretApp.switchAIService(to: "MLX Llama3.2-8B (Local)")
                        } catch {
                            logError(.ui, "Failed to switch AI Service: \(error)")
                            juuretApp.errorMessage = "Failed to switch AI Service: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.genealogyCallout)
                .controlSize(.small)
                
                Button("Mistral-7B") {
                    Task {
                        do {
                            try await juuretApp.switchAIService(to: "MLX Mistral-7B (Local)")
                        } catch {
                            logError(.ui, "Failed to switch AI Service: \(error)")
                            juuretApp.errorMessage = "Failed to switch AI Service: \(error.localizedDescription)"
                        }
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
                            // FIXED: Use correct method that exists in JuuretApp
                            await juuretApp.loadFile()
                            logInfo(.ui, "✅ File manually opened successfully")
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
            
            // Enhanced family members display
            enhancedFamilyMembersView(family: family)
        }
    }
    
    private func enhancedFamilyMembersView(family: Family) -> some View {
        VStack(alignment: .leading, spacing: 15) { // Increased spacing
            // Parents - FIXED: father is not optional in Family struct
            enhancedPersonView(person: family.father, in: family, role: "Father")
            
            if let mother = family.mother {
                enhancedPersonView(person: mother, in: family, role: "Mother")
            }
            
            // Children
            if !family.children.isEmpty {
                Text("Children:")
                    .font(.genealogyHeadline) // Enhanced font
                    .fontWeight(.semibold)
                    .padding(.top, 10)
                
                ForEach(family.children) { child in
                    enhancedPersonView(person: child, in: family, role: "Child")
                }
            }
        }
        .padding(16) // Increased padding
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
    
    private func enhancedPersonView(person: Person, in family: Family, role: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Person name (clickable for citation)
            Button(action: {
                showCitation(for: person, in: family)
            }) {
                Text("\(role): \(person.displayName)")
                    .font(.genealogySubheadline) // Enhanced font
                    .foregroundColor(.primary)
                    .underline()
            }
            .buttonStyle(.plain)
            
            // Birth date (clickable for Hiski)
            if let birthDate = person.birthDate {
                Button(action: {
                    showHiskiQuery(for: person, eventType: .birth)
                }) {
                    Text("Birth: \(birthDate)")
                        .font(.genealogyCallout) // Enhanced font
                        .foregroundColor(.blue)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            
            // Death date (clickable for Hiski)
            if let deathDate = person.deathDate {
                Button(action: {
                    showHiskiQuery(for: person, eventType: .death)
                }) {
                    Text("Death: \(deathDate)")
                        .font(.genealogyCallout) // Enhanced font
                        .foregroundColor(.blue)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            
            // Spouse (clickable for spouse citation)
            if let spouse = person.spouse {
                Button(action: {
                    showSpouseCitation(spouseName: spouse, in: family)
                }) {
                    Text("Spouse: \(spouse)")
                        .font(.genealogyCallout) // Enhanced font
                        .foregroundColor(.purple)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
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
    
    private func showHiskiQuery(for person: Person, eventType: EventType) {
        logInfo(.ui, "User requested Hiski query for: \(person.displayName) (\(eventType))")
        if let url = juuretApp.generateHiskiQuery(for: person, eventType: eventType) {
            hiskiResult = url
            showingHiskiResult = true
            logDebug(.citation, "Generated Hiski URL: \(hiskiResult)")
        } else {
            logWarn(.citation, "Insufficient data to generate Hiski URL")
        }
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

// MARK: - Preview

#Preview {
    NavigationView {
        JuuretView()
            .environment(JuuretApp())
    }
}

