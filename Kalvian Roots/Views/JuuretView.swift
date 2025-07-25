//
//  Simplified JuuretView.swift
//  Goes straight to family extraction when file is loaded
//

import SwiftUI
import UniformTypeIdentifiers

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
        VStack(spacing: 20) {
            if juuretApp.fileManager.isFileLoaded {
                // File is loaded - show family extraction interface
                familyExtractionInterface
            } else {
                // File not loaded - show simple error and open button
                fileNotLoadedInterface
            }
        }
        .padding()
        .navigationTitle("Kalvian Roots")
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
        .onAppear {
            logInfo(.ui, "JuuretView appeared")
        }
    }
    
    // MARK: - Family Extraction Interface (Main Interface)
    
    private var familyExtractionInterface: some View {
        VStack(spacing: 20) {
            // Simple header showing file is loaded
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Ready")
                    .foregroundColor(.green)
                Spacer()
                if let url = juuretApp.fileManager.currentFileURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            // Family ID input - the main interface
            VStack(alignment: .leading, spacing: 10) {
                Text("Family ID?")
                    .font(.title2)
                    .fontWeight(.medium)
                
                HStack {
                    TextField("e.g., Korpi 6", text: $familyId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
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
                    
                    Button("Complete") {
                        Task {
                            await extractFamilyComplete()
                        }
                    }
                    .disabled(familyId.isEmpty || juuretApp.isProcessing)
                    .buttonStyle(.bordered)
                    .help("Extract family + resolve cross-references")
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(10)
            
            // Processing status
            if juuretApp.isProcessing {
                processingStatusView
            }
            
            // Error display
            if let errorMessage = juuretApp.errorMessage, !juuretApp.isProcessing {
                errorDisplayView(errorMessage)
            }
            
            // Family display
            if let family = juuretApp.currentFamily {
                familyDisplaySection(family: family)
            }
            
            Spacer()
        }
    }
    
    // MARK: - File Not Loaded Interface (Error State)
    
    private var fileNotLoadedInterface: some View {
        VStack(spacing: 20) {
            // Simple file status
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.orange)
                Text("No file loaded")
                    .foregroundColor(.orange)
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
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)
            
            Spacer()
        }
    }
    
    // MARK: - Status Views (Simplified)
    
    private var processingStatusView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text(juuretApp.extractionProgress.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func errorDisplayView(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.red)
            }
            
            Text(errorMessage)
                .font(.body)
                .foregroundColor(.primary)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - Family Display (Unchanged)
    
    private func familyDisplaySection(family: Family) -> some View {
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
            
            // Child mortality info
            if let childrenDied = family.childrenDiedInfancy {
                Text("Children died in infancy: \(childrenDied)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 2)
    }
    
    // MARK: - Action Methods (Unchanged)
    
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
