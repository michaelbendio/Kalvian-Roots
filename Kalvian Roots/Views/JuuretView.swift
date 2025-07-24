//
//  JuuretView.swift
//  Kalvian Roots
//
//  Complete rewrite without Foundation Models Framework
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
    @State private var showingDebugSettings = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // AI SERVICE STATUS SECTION
                aiServiceStatusView
                
                // FILE STATUS SECTION
                fileStatusSection
                
                // DEBUG CONTROLS
                debugControlsSection
                
                // Family Input Section (only show if ready)
                if juuretApp.isReady {
                    inputSection
                    
                    // Processing Status
                    if juuretApp.isProcessing {
                        processingStatusView
                    }
                    
                    // Error Display
                    if let errorMessage = juuretApp.errorMessage, !juuretApp.isProcessing {
                        errorDisplayView(errorMessage)
                    }
                    
                    // Family Display
                    if let family = juuretApp.currentFamily {
                        familyLoadedIndicator(family)
                        familyDisplaySection(family: family)
                    }
                } else {
                    // Show setup instructions
                    setupInstructionsView
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Family Extraction")
        .sheet(isPresented: $showingDebugSettings) {
            DebugSettingsView()
                .environment(juuretApp)
        }
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
    
    // MARK: - AI Service Status Section
    
    private var aiServiceStatusView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Service Status")
                .font(.headline)
            
            HStack {
                if juuretApp.aiParsingService.isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("\(juuretApp.currentServiceName) Ready")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("API key configured")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text("\(juuretApp.currentServiceName) Not Configured")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("API key required")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Settings") {
                    showingDebugSettings = true
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            
            // Service switching
            HStack {
                Text("Current service:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Picker("AI Service", selection: Binding(
                    get: { juuretApp.currentServiceName },
                    set: { newValue in
                        Task {
                            logInfo(.ui, "User switching AI service to: \(newValue)")
                            await juuretApp.switchAIService(to: newValue)
                        }
                    }
                )) {
                    ForEach(juuretApp.availableServices, id: \.self) { service in
                        Text(service).tag(service)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - File Status Section
    
    private var fileStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Status")
                .font(.headline)
            
            HStack {
                if juuretApp.fileManager.isFileLoaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("File Loaded")
                            .font(.caption)
                            .foregroundColor(.green)
                        if let url = juuretApp.fileManager.currentFileURL {
                            Text(url.lastPathComponent)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Close File") {
                        logInfo(.ui, "User closing file")
                        juuretApp.fileManager.closeFile()
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
                        logInfo(.ui, "User opening file")
                        Task {
                            do {
                                _ = try await juuretApp.fileManager.openFile()
                                await juuretApp.updateFileContent()
                                logInfo(.ui, "File opened and content updated")
                            } catch {
                                logError(.ui, "Failed to open file: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Debug Controls Section
    
    private var debugControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Debug Controls")
                .font(.headline)
            
            HStack {
                Button("Load Sample Family") {
                    logInfo(.ui, "User loading sample family")
                    juuretApp.loadSampleFamily()
                }
                .buttonStyle(.bordered)
                .font(.caption)
                
                Button("Load Complex Family") {
                    logInfo(.ui, "User loading complex sample family")
                    juuretApp.loadComplexSampleFamily()
                }
                .buttonStyle(.bordered)
                .font(.caption)
                
                Button("Debug Settings") {
                    showingDebugSettings = true
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            
            // Quick log level controls
            HStack {
                Text("Log Level:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Button(level.description) {
                        DebugLogger.shared.setLevel(level)
                        logInfo(.ui, "Debug level changed to: \(level.description)")
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(getCurrentLogLevel() == level ? .blue : .secondary)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - Setup Instructions
    
    private var setupInstructionsView: some View {
        VStack(spacing: 15) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Setup Required")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("To extract families from Juuret Kälviällä text, you need:")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: juuretApp.aiParsingService.isConfigured ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(juuretApp.aiParsingService.isConfigured ? .green : .orange)
                    Text("AI Service API Key (\(juuretApp.currentServiceName))")
                }
                
                HStack {
                    Image(systemName: juuretApp.fileManager.isFileLoaded ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(juuretApp.fileManager.isFileLoaded ? .green : .orange)
                    Text("Juuret Kälviällä Text File")
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            HStack {
                if !juuretApp.aiParsingService.isConfigured {
                    Button("Configure AI Service") {
                        showingDebugSettings = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if !juuretApp.fileManager.isFileLoaded {
                    Button("Open File...") {
                        Task {
                            do {
                                _ = try await juuretApp.fileManager.openFile()
                                await juuretApp.updateFileContent()
                            } catch {
                                logError(.ui, "Failed to open file: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Family Extraction")
                .font(.headline)
            
            Text("🎉 Ready! AI service configured and Juuret Kälviällä text loaded.")
                .font(.caption)
                .foregroundColor(.green)
                .padding(.bottom, 5)
            
            HStack {
                TextField("Family ID (e.g., Korpi 6)", text: $familyId)
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
                
                Button("Extract + Resolve") {
                    Task {
                        await extractFamilyComplete()
                    }
                }
                .disabled(familyId.isEmpty || juuretApp.isProcessing)
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Status Views
    
    private var processingStatusView: some View {
        VStack(spacing: 10) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(juuretApp.extractionProgress.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if juuretApp.isResolvingCrossReferences {
                Text("Resolving family cross-references...")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
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
            
            if errorMessage.contains("not configured") {
                Button("Configure AI Service") {
                    showingDebugSettings = true
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
    
    private func familyLoadedIndicator(_ family: Family) -> some View {
        HStack {
            Text("✅ Family Loaded: \(family.familyId)")
                .font(.caption)
                .foregroundColor(.green)
            
            Spacer()
            
            if juuretApp.hasEnhancedFamily {
                Text("🔗 Cross-references resolved")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.bottom, 10)
    }
    
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
    
    // MARK: - Action Methods
    
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
    
    // MARK: - Helper Methods
    
    private func getCurrentLogLevel() -> LogLevel {
        return DebugLogger.shared.getCurrentSettings().level
    }
}

// MARK: - Debug Settings View

struct DebugSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JuuretApp.self) private var juuretApp
    @State private var apiKey = ""
    @State private var showingAPIKey = false
    @State private var selectedService = "DeepSeek"
    
    var body: some View {
        NavigationView {
            Form {
                Section("AI Service Configuration") {
                    Picker("AI Service", selection: $selectedService) {
                        ForEach(juuretApp.availableServices, id: \.self) { service in
                            Text(service).tag(service)
                        }
                    }
                    .onChange(of: selectedService) { _, newValue in
                        Task {
                            await juuretApp.switchAIService(to: newValue)
                        }
                    }
                    
                    HStack {
                        if showingAPIKey {
                            TextField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(showingAPIKey ? "Hide" : "Show") {
                            showingAPIKey.toggle()
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Button("Save API Key") {
                        Task {
                            await juuretApp.configureAIService(apiKey: apiKey)
                            apiKey = "" // Clear after saving
                        }
                    }
                    .disabled(apiKey.isEmpty)
                    
                    // Service status
                    ForEach(juuretApp.getAIServiceStatus(), id: \.name) { status in
                        HStack {
                            Circle()
                                .fill(status.configured ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(status.name)
                            Spacer()
                            Text(status.configured ? "Configured" : "Not Configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Debug Settings") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Log Level")
                            .font(.headline)
                        
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Button(action: {
                                DebugLogger.shared.setLevel(level)
                            }) {
                                HStack {
                                    Text(level.description)
                                    Spacer()
                                    if DebugLogger.shared.getCurrentSettings().level == level {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Log Categories")
                            .font(.headline)
                        
                        ForEach(LogCategory.allCases, id: \.self) { category in
                            Button(action: {
                                let currentCategories = DebugLogger.shared.getCurrentSettings().categories
                                if currentCategories.contains(category) {
                                    DebugLogger.shared.disableCategory(category)
                                } else {
                                    DebugLogger.shared.enableCategory(category)
                                }
                            }) {
                                HStack {
                                    Text("\(category.emoji) \(category.rawValue)")
                                    Spacer()
                                    if DebugLogger.shared.getCurrentSettings().categories.contains(category) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button("Enable All Categories") {
                            DebugLogger.shared.enableAllCategories()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Section("Statistics") {
                    let stats = juuretApp.getResolutionStatistics()
                    
                    HStack {
                        Text("Cross-reference attempts:")
                        Spacer()
                        Text("\(stats.totalAttempts)")
                    }
                    
                    HStack {
                        Text("Success rate:")
                        Spacer()
                        Text("\(String(format: "%.1f", stats.successRate * 100))%")
                    }
                    
                    let nameStats = juuretApp.getNameEquivalenceReport()
                    
                    HStack {
                        Text("Name equivalences learned:")
                        Spacer()
                        Text("\(nameStats.learnedCount)")
                    }
                    
                    Button("Reset Statistics") {
                        juuretApp.resetStatistics()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .navigationTitle("Debug Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            selectedService = juuretApp.currentServiceName
            logInfo(.ui, "Debug settings view opened")
        }
    }
}
