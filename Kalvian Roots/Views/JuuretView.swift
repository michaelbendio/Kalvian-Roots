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
        VStack(spacing: 15) {
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
        VStack(alignment: .leading, spacing: 12) { // Increased spacing
            // Enhanced family header
            VStack(alignment: .leading, spacing: 6) {
                Text(family.familyId)
                    .font(.genealogyTitle) // Much larger title
                    .fontWeight(.bold)
                Text("Pages \(family.pageReferences.joined(separator: ", "))")
                    .font(.genealogyCallout) // Enhanced font
                    .foregroundColor(.secondary)
            }
            
            // Compact click instructions
            Text("💡 Click names for citations, dates for Hiski queries, purple spouse names for spouse citations")
                .font(.genealogyCaption) // Enhanced font
                .foregroundColor(.blue)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            // Enhanced family members display
            enhancedFamilyMembersView(family: family)
        }
    }
    
    // Helper function to format marriage date
    private func formatMarriageDate(_ date: String) -> String {
        // Handle different date formats
        if date.count == 2 {
            // Convert 2-digit year to 4-digit (assuming 1700s or 1800s)
            if let year = Int(date) {
                // Use 1700s for years > 50, 1800s for years <= 50
                let century = year > 50 ? 1700 : 1800
                return String(century + year)
            }
        } else if date.count == 8 || date.count == 10 {
            // Already a full date like 14.10.1750
            return date
        }
        return date
    }
    
    private func enhancedPersonView(person: Person, in family: Family) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Person name (clickable for citation)
            Button(action: {
                showCitation(for: person, in: family)
            }) {
                Text("\(person.displayName)")
                    .font(.genealogySubheadline) // Enhanced font
                    .foregroundColor(.primary)
                    .underline()
            }
            .buttonStyle(.plain)
            
            // Birth and death dates in same line for compactness
            HStack(spacing: 16) {
                if let birthDate = person.birthDate {
                    Button(action: {
                        showHiskiQuery(for: person, eventType: .birth)
                    }) {
                        Text("Birth: \(birthDate)")
                            .font(.genealogyCallout)
                            .foregroundColor(.blue)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                
                if let deathDate = person.deathDate {
                    Button(action: {
                        showHiskiQuery(for: person, eventType: .death)
                    }) {
                        Text("Death: \(deathDate)")
                            .font(.genealogyCallout)
                            .foregroundColor(.blue)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
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
        .padding(.vertical, 4)
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

extension JuuretView {
    
    // MARK: - Simplified Family Members View
    // Breaking up the complex enhancedFamilyMembersView into smaller pieces
    
    private func enhancedFamilyMembersView(family: Family) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Parents section
            parentsSection(family: family)
            
            // Marriage section
            marriageSection(family: family)
            
            // Additional spouses section
            additionalSpousesSection(family: family)
            
            // Children section
            childrenSection(family: family)
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - Component Views (Breaking up complex expression)
    
    @ViewBuilder
    private func parentsSection(family: Family) -> some View {
        if let father = family.father {
            enhancedPersonView(person: father, in: family, role: "Father")
        }
        
        if let mother = family.mother {
            enhancedPersonView(person: mother, in: family, role: "Mother")
        }
    }
    
    @ViewBuilder
    private func marriageSection(family: Family) -> some View {
        if let primaryCouple = family.primaryCouple,
           let marriageDate = primaryCouple.marriageDate {
            marriageDateView(marriageDate: marriageDate, family: family)
                .padding(.vertical, 2)
        }
    }
    
    private func marriageDateView(marriageDate: String, family: Family) -> some View {
        HStack {
            Text("Married:")
                .font(.genealogyCallout)
                .foregroundColor(.secondary)
                .padding(.leading, 20)
            
            marriageDateButton(marriageDate: marriageDate, family: family)
        }
    }
    
    private func marriageDateButton(marriageDate: String, family: Family) -> some View {
        Button(action: {
            if let father = family.father {
                showHiskiQuery(for: father, eventType: .marriage)
            }
        }) {
            Text(formatMarriageDate(marriageDate))
                .font(.genealogyCallout)
                .foregroundColor(.blue)
                .underline()
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func additionalSpousesSection(family: Family) -> some View {
        if family.couples.count > 1 {
            let additionalCouples = Array(family.couples.dropFirst().enumerated())
            ForEach(additionalCouples, id: \.offset) { index, couple in
                additionalSpouseView(index: index, couple: couple, family: family)
            }
        }
    }
    
    private func additionalSpouseView(index: Int, couple: Couple, family: Family) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Additional Spouse \(index + 2):")
                .font(.genealogyCallout)
                .fontWeight(.semibold)
                .padding(.top, 8)
            
            enhancedPersonView(person: couple.wife, in: family, role: "Wife")
            
            additionalSpouseMarriageDate(couple: couple)
        }
    }
    
    @ViewBuilder
    private func additionalSpouseMarriageDate(couple: Couple) -> some View {
        if let marriageDate = couple.marriageDate {
            HStack {
                Text("Married:")
                    .font(.genealogyCallout)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
                
                Text(formatMarriageDate(marriageDate))
                    .font(.genealogyCallout)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 2)
        }
    }
    
    @ViewBuilder
    private func childrenSection(family: Family) -> some View {
        if !family.children.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Children:")
                    .font(.genealogyHeadline)
                    .fontWeight(.semibold)
                    .padding(.top, 6)
                
                childrenList(children: family.children, family: family)
            }
        }
    }
    
    private func childrenList(children: [Person], family: Family) -> some View {
        ForEach(children) { child in
            enhancedPersonView(person: child, in: family, role: "Child")
        }
    }
    
    // MARK: - Simplified Person View with role parameter
    
    private func enhancedPersonView(person: Person, in family: Family, role: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Person name button
            personNameButton(person: person, family: family)
            
            // Birth and death dates
            personDatesView(person: person)
            
            // Spouse information
            personSpouseView(person: person, family: family)
        }
        .padding(.vertical, 4)
    }
    
    private func personNameButton(person: Person, family: Family) -> some View {
        Button(action: {
            showCitation(for: person, in: family)
        }) {
            Text(person.displayName)
                .font(.genealogySubheadline)
                .foregroundColor(.primary)
                .underline()
        }
        .buttonStyle(.plain)
    }
    
    private func personDatesView(person: Person) -> some View {
        HStack(spacing: 16) {
            if let birthDate = person.birthDate {
                birthDateButton(person: person, birthDate: birthDate)
            }
            
            if let deathDate = person.deathDate {
                deathDateButton(person: person, deathDate: deathDate)
            }
        }
    }
    
    private func birthDateButton(person: Person, birthDate: String) -> some View {
        Button(action: {
            showHiskiQuery(for: person, eventType: .birth)
        }) {
            Text("Birth: \(birthDate)")
                .font(.genealogyCallout)
                .foregroundColor(.blue)
                .underline()
        }
        .buttonStyle(.plain)
    }
    
    private func deathDateButton(person: Person, deathDate: String) -> some View {
        Button(action: {
            showHiskiQuery(for: person, eventType: .death)
        }) {
            Text("Death: \(deathDate)")
                .font(.genealogyCallout)
                .foregroundColor(.blue)
                .underline()
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func personSpouseView(person: Person, family: Family) -> some View {
        if let spouse = person.spouse {
            Button(action: {
                showSpouseCitation(spouseName: spouse, in: family)
            }) {
                Text("Spouse: \(spouse)")
                    .font(.genealogyCallout)
                    .foregroundColor(.purple)
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }
}

