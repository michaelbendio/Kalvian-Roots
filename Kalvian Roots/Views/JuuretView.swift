//
//  JuuretView.swift
//  Kalvian Roots
//
//  Enhanced with file management integration
//

import SwiftUI
import FoundationModels

struct JuuretView: View {
    @Environment(JuuretApp.self) var app
    @State private var familyId = ""
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
                
                // FILE STATUS SECTION
                fileStatusSection
                
                // Family Input Section (only show if file loaded and Foundation Models available)
                if app.isReady && systemModel.availability == .available {
                    inputSection
                    
                    // Extraction Status
                    if app.isProcessing {
                        extractionStatus
                    }
                    
                    // Family Display
                    if let family = app.currentFamily {
                        Text("✅ Family Loaded: \(family.familyId)")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.bottom, 10)
                        
                        familyDisplaySection(family: family)
                    }
                } else if !app.isReady {
                    // Show file loading instructions
                    fileLoadingInstructions
                } else {
                    Text("Foundation Models not available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
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
    
    // MARK: - File Status Section
    
    var fileStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Status")
                .font(.headline)
            
            HStack {
                if app.fileManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading file...")
                        .font(.caption)
                } else if app.fileManager.isFileLoaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("File Loaded")
                            .font(.caption)
                            .foregroundColor(.green)
                        if let url = app.fileManager.currentFileURL {
                            Text(url.lastPathComponent)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Close File") {
                        app.fileManager.closeFile()
                    }
                    .font(.caption)
                } else {
                    Image(systemName: "doc.text")
                        .foregroundColor(.orange)
                    Text("No file loaded")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("Open File...") {
                        Task {
                            do {
                                try await app.fileManager.openFileDialog()
                            } catch {
                                print("❌ Failed to open file: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            // Show any file manager errors
            if let errorMessage = app.fileManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 5)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - File Loading Instructions
    
    var fileLoadingInstructions: some View {
        VStack(spacing: 15) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Load Juuret Kälviällä Text")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("To extract families, you need to load the Juuret Kälviällä genealogy text file.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("The app will automatically look for:")
                    .font(.headline)
                
                Text("• JuuretKälviällä.roots in iCloud Documents")
                Text("• JuuretKälviällä.roots in local Documents")
                
                Text("Or use File → Open... to select the file manually")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            Button("Open File...") {
                Task {
                    do {
                        try await app.fileManager.openFileDialog()
                    } catch {
                        print("❌ Failed to open file: \(error)")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
    
    // MARK: - Input Section (existing)
    
    var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Family Extraction")
                .font(.headline)
            
            Text("🎉 Real Juuret Kälviällä text loaded! Foundation Models will extract from actual genealogical data.")
                .font(.caption)
                .foregroundColor(.green)
                .padding(.bottom, 5)
            
            HStack {
                TextField("Family ID (e.g., Korpi 6)", text: $familyId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        if !familyId.isEmpty && !app.isProcessing {
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
                .disabled(familyId.isEmpty || app.isProcessing)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Rest of existing methods...
    
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
            Text("Extracting family from real Juuret Kälviällä text...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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
    
    // MARK: - Action Methods
    
    func extractFamily() async {
        print("🚀 extractFamily() called from UI")
        
        do {
            try await app.extractFamily(familyId: familyId.uppercased())
            print("✅ extractFamily() completed successfully")
        } catch {
            print("❌ Extraction error: \(error)")
        }
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
