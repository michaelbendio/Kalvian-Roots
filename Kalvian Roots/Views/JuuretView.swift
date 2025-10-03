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
        .setupHiskiSafariHost()
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
                juuretApp.closeHiskiWebViews()
            }
            Button("OK") {
                juuretApp.closeHiskiWebViews()
            }
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
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Fatal Error", isPresented: $showingFatalError) {
            Button("Quit", role: .destructive) {
                #if os(macOS)
                NSApplication.shared.terminate(nil)
                #endif
            }
        } message: {
            Text(juuretApp.errorMessage ?? "Unknown error")
                .font(.genealogyMonospaceSmall)
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
            familyInputSection
            
            if juuretApp.isProcessing {
                processingStatusView
            }
            
            if let errorMessage = juuretApp.errorMessage {
                errorDisplayView(errorMessage)
            }
            
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
            
            if let statusMessage = juuretApp.familyNetworkCache.statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(statusMessage)
                        .font(.genealogyCallout)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var processingStatusView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            Text("Processing family...")
                .font(.genealogyCallout)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func errorDisplayView(_ errorMessage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(errorMessage)
                .font(.genealogyCallout)
                .foregroundColor(.red)
        }
        .padding(20)
        .background(Color.red.opacity(0.05))
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
            if let primaryCouple = family.primaryCouple {
                parentsSection(primaryCouple: primaryCouple, family: family)
            }
            
            if !allChildren.isEmpty {
                childrenSection(children: allChildren, family: family)
            }
            
            if family.couples.count > 1 {
                additionalSpousesSection(family: family)
            }
            
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
                enhancedDeathDate: nil,
                enhancedMarriageDate: nil,
                onNameClick: { person in
                    generateCitation(for: person, in: family)
                },
                onDateClick: { date, eventType in
                    Task {
                        let result = await juuretApp.processHiskiQuery(
                            for: primaryCouple.husband,
                            eventType: eventType,
                            familyId: family.familyId
                        )
                        hiskiResult = result
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
                enhancedDeathDate: nil,
                enhancedMarriageDate: nil,
                onNameClick: { person in
                    generateCitation(for: person, in: family)
                },
                onDateClick: { date, eventType in
                    Task {
                        let result = await juuretApp.processHiskiQuery(
                            for: primaryCouple.wife,
                            eventType: eventType,
                            familyId: family.familyId
                        )
                        hiskiResult = result
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
                    enhancedDeathDate: getEnhancedDeathDate(for: child, in: family),
                    enhancedMarriageDate: getEnhancedMarriageDate(for: child, in: family),
                    onNameClick: { person in
                        generateCitation(for: person, in: family)
                    },
                    onDateClick: { date, eventType in
                        Task {
                            let result = await juuretApp.processHiskiQuery(
                                for: child,
                                eventType: eventType,
                                familyId: family.familyId
                            )
                            hiskiResult = result
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
                .padding(.leading, 50)
            }
        }
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
    
    private func additionalSpouseView(couple: Couple, index: Int, family: Family) -> some View {
        let actualCoupleIndex = index + 1
        let previousCouple = family.couples[actualCoupleIndex - 1]
        
        let isHusbandContinuing = couple.husband.name == previousCouple.husband.name &&
                                  couple.husband.birthDate == previousCouple.husband.birthDate
        
        let isWifeContinuing = couple.wife.name == previousCouple.wife.name &&
                              couple.wife.birthDate == previousCouple.wife.birthDate

        let additionalSpouse: Person
        if isHusbandContinuing && !isWifeContinuing {
            additionalSpouse = couple.wife
        } else if isWifeContinuing && !isHusbandContinuing {
            additionalSpouse = couple.husband
        } else {
            additionalSpouse = couple.wife
        }
        
        return VStack(alignment: .leading, spacing: 8) {
            PersonRowView(
                person: additionalSpouse,
                role: "Spouse",
                enhancedDeathDate: nil,
                enhancedMarriageDate: nil,
                onNameClick: { person in
                    handleAdditionalSpouseClick(person: person, family: family)
                },
                onDateClick: { date, eventType in
                    Task {
                        let result = await juuretApp.processHiskiQuery(
                            for: additionalSpouse,
                            eventType: eventType,
                            familyId: family.familyId
                        )
                        hiskiResult = result
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
            
            if let widowInfo = extractWidowInfo(for: additionalSpouse, from: family.notes, spouseIndex: index) {
                Text("(widow of \(widowInfo))")
                    .font(.genealogyCaption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.leading, 25)
            }
            
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
                    enhancedDeathDate: getEnhancedDeathDate(for: child, in: family),
                    enhancedMarriageDate: getEnhancedMarriageDate(for: child, in: family),
                    onNameClick: { person in
                        generateCitation(for: person, in: family)
                    },
                    onDateClick: { date, eventType in
                        Task {
                            let result = await juuretApp.processHiskiQuery(
                                for: child,
                                eventType: eventType,
                                familyId: family.familyId
                            )
                            hiskiResult = result
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
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func notesSection(notes: [String]) -> some View {
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
    
    // MARK: - Helper Methods
    
    /// Get enhanced death date for a person from their asParent family
    private func getEnhancedDeathDate(for person: Person, in family: Family) -> String? {
        guard let network = juuretApp.familyNetworkWorkflow?.getFamilyNetwork() else {
            return person.deathDate
        }
        
        guard let asParentFamily = network.getAsParentFamily(for: person) else {
            return person.deathDate
        }
        
        let asParentPerson = asParentFamily.allParents.first { parent in
            parent.name.lowercased() == person.name.lowercased() ||
            (parent.birthDate == person.birthDate && parent.birthDate != nil)
        }
        
        return asParentPerson?.deathDate ?? person.deathDate
    }
    
    /// Get enhanced marriage date for a person from their asParent family
    private func getEnhancedMarriageDate(for person: Person, in family: Family) -> String? {
        guard let network = juuretApp.familyNetworkWorkflow?.getFamilyNetwork() else {
            return person.fullMarriageDate ?? person.marriageDate
        }
        
        guard let asParentFamily = network.getAsParentFamily(for: person) else {
            return person.fullMarriageDate ?? person.marriageDate
        }
        
        let asParentPerson = asParentFamily.allParents.first { parent in
            parent.name.lowercased() == person.name.lowercased() ||
            (parent.birthDate == person.birthDate && parent.birthDate != nil)
        }
        
        let matchingCouple = asParentFamily.couples.first { couple in
            couple.husband.name.lowercased() == person.name.lowercased() ||
            couple.wife.name.lowercased() == person.name.lowercased()
        }
        
        return asParentPerson?.fullMarriageDate
            ?? matchingCouple?.fullMarriageDate
            ?? asParentPerson?.marriageDate
            ?? person.fullMarriageDate
            ?? person.marriageDate
    }
    
    private func handleAdditionalSpouseClick(person: Person, family: Family) {
        if person.asChild != nil {
            generateCitation(for: person, in: family)
        } else {
            alertTitle = "No Reference Available"
            alertMessage = "\(person.displayName) has no as_child reference in the source data. Showing citation for the main family instead."
            showingAlert = true
            generateCitation(for: person, in: family)
        }
    }
    
    private func formatDateDisplay(_ date: String) -> String {
        if date.count == 2 {
            if let year = Int(date) {
                let century = year < 50 ? "19" : "18"
                return "\(century)\(date)"
            }
        }
        return date
    }
    
    private func extractWidowInfo(for person: Person, from notes: [String], spouseIndex: Int) -> String? {
        let widowNotes = notes.filter { $0.lowercased().contains("leski") }
        
        if spouseIndex < widowNotes.count {
            let note = widowNotes[spouseIndex]
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
