// JuuretView.swift
import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct JuuretView: View {
    @Environment(JuuretApp.self) private var juuretApp
    @State private var familyId = ""
    @State private var showingCitation = false
    @State private var citationText = ""
    @State private var showingHiskiResult = false
    @State private var hiskiResult = ""
    @State private var showingSpouseCitation = false
    @State private var spouseCitationText = ""
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingFatalError = false
    
    var body: some View {
        VStack(spacing: 15) {
            if juuretApp.fileManager.isFileLoaded {
                familyExtractionInterface
            } else {
                Color.clear
            }
        }
        .padding(20)
        .navigationTitle("Kalvian Roots")
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                CachedFamiliesMenu()
            }
        }
        #elseif os(iOS) || os(visionOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                CachedFamiliesMenu()
            }
        }
        #endif
        
        .alert("Citation", isPresented: $showingCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(citationText)
            }
            Button("OK") { }
        } message: {
            Text(citationText)
                .font(.genealogyCallout)
        }
        .alert("Hiski Query Result", isPresented: $showingHiskiResult) {
            Button("Copy URL") {
                copyToClipboard(hiskiResult)
            }
            Button("OK") { }
        } message: {
            Text(hiskiResult)
                .font(.genealogyCallout)
        }
        .alert("Spouse Citation", isPresented: $showingSpouseCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(spouseCitationText)
            }
            Button("OK") { }
        } message: {
            Text(spouseCitationText)
                .font(.genealogyCallout)
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("Error", isPresented: Binding(
            get: { juuretApp.errorMessage != nil },
            set: { if !$0 { juuretApp.errorMessage = nil } }
        )) {
            Button("Copy Details") {
                if let text = juuretApp.errorMessage {
                    #if os(macOS)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    #else
                    UIPasteboard.general.string = text
                    #endif
                }
            }
            Button("OK") { juuretApp.errorMessage = nil }
        } message: {
            Text(juuretApp.errorMessage ?? "Unknown error")
                .font(.genealogyMonospaceSmall)
        }
        .alert("Fatal Error: Canonical File Not Found", isPresented: $showingFatalError) {
            Button("Quit", role: .destructive) {
                #if os(macOS)
                NSApplication.shared.terminate(nil)
                #else
                fatalError("JuuretKälviällä.roots not found at canonical location")
                #endif
            }
        } message: {
            Text("""
                JuuretKälviällä.roots must be in:
                ~/Library/Mobile Documents/iCloud~com~michael-bendio~Kalvian-Roots/Documents/
                
                First line must be: canonical
                Second line must be: blank
                """)
        }
        .onAppear {
            logInfo(.ui, "JuuretView appeared")
            Task {
                await juuretApp.fileManager.autoLoadDefaultFile()
                if !juuretApp.fileManager.isFileLoaded {
                    showingFatalError = true
                }
            }
        }
    }
    
    // MARK: - Main Interface Views
    
    private var familyExtractionInterface: some View {
        VStack(spacing: 20) {
            // Simplified input section at the top
            familyInputSection
            
            // Show processing status if processing
            if juuretApp.isProcessing {
                processingStatusView
            }
            
            // Show error if there's an error
            if let errorMessage = juuretApp.errorMessage {
                errorDisplayView(errorMessage)
            }
            
            // CACHE CLEAR BUTTON - Always visible when cache has items
            if juuretApp.familyNetworkCache.cachedFamilyCount > 0 {
                Button(action: {
                    juuretApp.familyNetworkCache.clearCache()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear Cache (\(juuretApp.familyNetworkCache.cachedFamilyCount) families)")
                            .font(.genealogyCaption)
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            // Show family if extracted
            if let family = juuretApp.currentFamily {
                ScrollView {
                    familyDisplaySection(family: family)
                }
            }
        }
    }
    
    // MARK: - Family Input Section
    
    private var familyInputSection: some View {
        VStack(spacing: 12) {
            // Family ID input with "Citations for" label
            HStack {
                Text("Citations for")
                    .font(.genealogyHeadline)
                    .foregroundColor(.secondary)
                
                TextField("Family ID", text: $familyId)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        extractFamily()
                    }
                    .disabled(juuretApp.isProcessing)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal)
            .frame(maxWidth: 600)
            
            // NEXT BUTTON - Shows when next family is ready
            if juuretApp.familyNetworkCache.nextFamilyReady,
               let nextId = juuretApp.familyNetworkCache.nextFamilyId {
                Button(action: {
                    Task {
                        await juuretApp.loadNextFamily()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.forward.circle.fill")
                        Text("Next: \(nextId)")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3), value: juuretApp.familyNetworkCache.nextFamilyReady)
            }
            
            // STATUS MESSAGE - Shows "KLEEMOLA 6 ready" when families are cached
            if let statusMessage = juuretApp.familyNetworkCache.statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text(statusMessage)
                        .font(.genealogyCaption)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3), value: statusMessage)
            }
            
            // ERROR DISPLAY - Shows if background processing failed
            if let error = juuretApp.familyNetworkCache.backgroundError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.genealogyCaption)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Status Views
    
    private var processingStatusView: some View {
        HStack(spacing: 15) {
            ProgressView()
                .scaleEffect(1.0)
            Text(juuretApp.extractionProgress.description)
                .font(.genealogySubheadline)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func errorDisplayView(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.genealogySubheadline)
                Text("Error")
                    .font(.genealogyHeadline)
                    .foregroundColor(.red)
            }
            
            Text(errorMessage)
                .font(.genealogyBody)
                .foregroundColor(.primary)
                .padding(16)
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
        }
        .padding(20)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Family Display
    
    private func familyDisplaySection(family: Family) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(family.familyId)
                    .font(.genealogyTitle)
                    .fontWeight(.bold)
                Text("Pages \(family.pageReferences.joined(separator: ", "))")
                    .font(.genealogyCallout)
                    .foregroundColor(.secondary)
            }
            
            familyMembersView(family: family)
        }
    }
    
    private func familyMembersView(family: Family) -> some View {
        let allChildren = family.couples.flatMap { $0.children }
        
        return VStack(alignment: .leading, spacing: 20) {
            // Parents section
            if let primaryCouple = family.primaryCouple {
                parentsSection(primaryCouple: primaryCouple, family: family)
            }
            
            // Children section
            if !allChildren.isEmpty {
                childrenSection(children: allChildren, family: family)
            }
            
            // Additional Spouses section
            if family.couples.count > 1 {
                additionalSpousesSection(family: family)
            }
            
            // Notes section
            if !family.notes.isEmpty {
                notesSection(notes: family.notes)
            }
        }
    }
    
    // MARK: - Family Section Views
    
    @ViewBuilder
    private func parentsSection(primaryCouple: Couple, family: Family) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parents")
                .font(.genealogyHeadline)
                .fontWeight(.semibold)
            
            PersonRowView(
                person: primaryCouple.husband,
                role: "Father",
                onNameClick: { person in
                    generateCitation(for: person, in: family)
                },
                onDateClick: { date, eventType in
                    if let query = juuretApp.generateHiskiQuery(for: primaryCouple.husband, eventType: eventType) {
                        hiskiResult = query
                        showingHiskiResult = true
                    }
                },
                onSpouseClick: { spouseName in
                    Task {
                        let citation = await juuretApp.generateSpouseCitation(for: spouseName, in: family)
                        citationText = citation
                        showingCitation = true
                    }
                }
            )
            
            PersonRowView(
                person: primaryCouple.wife,
                role: "Mother",
                onNameClick: { person in
                    generateCitation(for: person, in: family)
                },
                onDateClick: { date, eventType in
                    if let query = juuretApp.generateHiskiQuery(for: primaryCouple.wife, eventType: eventType) {
                        hiskiResult = query
                        showingHiskiResult = true
                    }
                },
                onSpouseClick: { spouseName in
                    Task {
                        let citation = await juuretApp.generateSpouseCitation(for: spouseName, in: family)
                        citationText = citation
                        showingCitation = true
                    }
                }
            )
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func childrenSection(children: [Person], family: Family) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Children (\(children.count))")
                .font(.genealogyHeadline)
                .fontWeight(.semibold)
            
            ForEach(children) { child in
                PersonRowView(
                    person: child,
                    role: "Child",
                    onNameClick: { person in
                        generateCitation(for: person, in: family)
                    },
                    onDateClick: { date, eventType in
                        if let query = juuretApp.generateHiskiQuery(for: child, eventType: eventType) {
                            hiskiResult = query
                            showingHiskiResult = true
                        }
                    },
                    onSpouseClick: { spouseName in
                        Task {
                            let citation = await juuretApp.generateSpouseCitation(for: spouseName, in: family)
                            citationText = citation
                            showingCitation = true
                        }
                    }
                )
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func additionalSpousesSection(family: Family) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Additional Spouses")
                .font(.genealogyHeadline)
                .fontWeight(.semibold)
            
            ForEach(Array(family.couples.dropFirst().enumerated()), id: \.offset) { index, couple in
                additionalSpouseView(couple: couple, index: index, family: family)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func additionalSpouseView(couple: Couple, index: Int, family: Family) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Determine which spouse is the additional one
            let isHusbandSame = (index == 0 && couple.husband.name == family.primaryCouple?.husband.name) ||
                               (index > 0 && couple.husband.name == family.couples[index].husband.name)
            
            let additionalSpouse = isHusbandSame ? couple.wife : couple.husband
            
            PersonRowView(
                person: additionalSpouse,
                role: "Spouse",
                onNameClick: { person in
                    handleAdditionalSpouseClick(person: person, family: family)
                },
                onDateClick: { date, eventType in
                    if let query = juuretApp.generateHiskiQuery(for: additionalSpouse, eventType: eventType) {
                        hiskiResult = query
                        showingHiskiResult = true
                    }
                },
                onSpouseClick: { spouseName in
                    Task {
                        let citation = await juuretApp.generateSpouseCitation(for: spouseName, in: family)
                        citationText = citation
                        showingCitation = true
                    }
                }
            )
            
            // Show widow/widower information if available - PASS THE INDEX
            if let widowInfo = extractWidowInfo(for: additionalSpouse, from: family.notes, spouseIndex: index) {
                Text("(widow of \(widowInfo))")
                    .font(.genealogyCaption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.leading, 25)
            }
            
            // Marriage date with this spouse
            if let marriageDate = couple.marriageDate {
                HStack(spacing: 4) {
                    Text("∞")
                        .font(.system(size: 15))
                    Text(formatDateDisplay(marriageDate))
                        .font(.genealogyCaption)
                }
                .padding(.leading, 25)
                .foregroundColor(.secondary)
            }
            
            // Children with this spouse
            if !couple.children.isEmpty {
                additionalSpouseChildren(children: couple.children, family: family)
            }
        }
    }
    
    @ViewBuilder
    private func additionalSpouseChildren(children: [Person], family: Family) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Children with this spouse:")
                .font(.genealogyCaption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
                .padding(.leading, 25)
            
            ForEach(children) { child in
                PersonRowView(
                    person: child,
                    role: "Child",
                    onNameClick: { person in
                        generateCitation(for: person, in: family)
                    },
                    onDateClick: { date, eventType in
                        if let query = juuretApp.generateHiskiQuery(for: child, eventType: eventType) {
                            hiskiResult = query
                            showingHiskiResult = true
                        }
                    },
                    onSpouseClick: { spouseName in
                        Task {
                            let citation = await juuretApp.generateSpouseCitation(for: spouseName, in: family)
                            citationText = citation
                            showingCitation = true
                        }
                    }
                )
                .padding(.leading, 25)
            }
        }
    }
    
    @ViewBuilder
    private func notesSection(notes: [String]) -> some View {
        // Filter out widow/widower notes (those containing "leski")
        let filteredNotes = notes.filter { !$0.lowercased().contains("leski") }
        
        if !filteredNotes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.genealogyHeadline)
                    .fontWeight(.semibold)
                
                ForEach(filteredNotes, id: \.self) { note in
                    Text(note)
                        .font(.genealogyBody)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .background(Color.yellow.opacity(0.05))
            .cornerRadius(10)
        }
    }
    
    private func handleAdditionalSpouseClick(person: Person, family: Family) {
        if person.asChild != nil {
            generateCitation(for: person, in: family)
        } else {
            // Show modal error message but still generate main family citation
            alertTitle = "No Reference Available"
            alertMessage = "\(person.displayName) has no as_child reference in the source data. Showing citation for the main family instead."
            showingAlert = true
            
            // Generate citation for the main family (unenhanced)
            Task {
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                citationText = citation
                // Show citation alert after the warning alert
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingCitation = true
                }
            }
        }
    }
    
    // Helper function to format date for display
    private func formatDateDisplay(_ date: String) -> String {
        // If it's a 2-digit year, add "17" or "18" prefix
        if date.count == 2 {
            if let year = Int(date) {
                let century = year < 30 ? "18" : "17"
                return "\(century)\(date)"
            }
        }
        // Otherwise return as-is
        return date
    }
    
    // Helper function to extract widow information from notes
    private func extractWidowInfo(for person: Person, from notes: [String], spouseIndex: Int) -> String? {
        // Extract all widow notes in order
        let widowNotes = notes.filter { $0.lowercased().contains("leski") }
        
        // Use the spouse index to match the correct widow note
        // Index 0 = II puoliso (first additional spouse)
        // Index 1 = III puoliso (second additional spouse)
        if spouseIndex < widowNotes.count {
            let note = widowNotes[spouseIndex]
            // Extract the name before "leski"
            let components = note.components(separatedBy: " leski")
            if components.count > 0 {
                return components[0].trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    // MARK: - Actions
    
    private func extractFamily() {
        guard !familyId.isEmpty else { return }
        
        Task {
            await juuretApp.extractFamily(familyId: familyId.uppercased())
        }
    }
    
    private func generateCitation(for person: Person, in family: Family) {
        Task {
            let citation = await juuretApp.generateCitation(for: person, in: family)
            citationText = citation
            showingCitation = true
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        
        logInfo(.ui, "📋 Copied to clipboard: \(text.prefix(100))...")
    }
}

// MARK: - Supporting Type

enum PersonRole {
    case father, mother, child
    
    var icon: String {
        switch self {
        case .father: return "person.fill"
        case .mother: return "person.fill"
        case .child: return "person"
        }
    }
    
    var color: Color {
        switch self {
        case .father, .mother: return .blue
        case .child: return .green
        }
    }
}

// MARK: - Font Extensions

extension Font {
    static let genealogyTitle = Font.system(size: 24, weight: .bold)
    static let genealogyHeadline = Font.system(size: 20, weight: .semibold)
    static let genealogySubheadline = Font.system(size: 18)
    static let genealogyBody = Font.system(size: 16)
    static let genealogyCallout = Font.system(size: 15)
    static let genealogyCaption = Font.system(size: 14)
    static let genealogyMonospaceSmall = Font.system(size: 13, design: .monospaced)
}

// MARK: - Preview

#Preview {
    JuuretView()
        .environment(JuuretApp())
}
