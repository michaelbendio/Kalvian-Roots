// JuuretView.swift - Simplified Version
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
    
    #if os(iOS)
    @State private var showingFilePicker = false
    #endif
    
    var body: some View {
        VStack(spacing: 15) {
            if juuretApp.fileManager.isFileLoaded {
                familyExtractionInterface
            } else {
                fileNotLoadedInterface
            }
        }
        .padding(20)
        .navigationTitle("Kalvian Roots")
        #if os(iOS)
        .sheet(isPresented: $showingFilePicker) {
            DocumentPickerView { url in
                Task {
                    await processSelectedFile(url)
                }
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
        .onAppear {
            logInfo(.ui, "JuuretView appeared")
        }
    }
    
    // MARK: - File Processing for iOS
    
    #if os(iOS)
    private func processSelectedFile(_ url: URL) async {
        logInfo(.ui, "📂 Processing selected file: \(url.lastPathComponent)")
        
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let content = try String(contentsOf: url, encoding: .utf8)
            
            await MainActor.run {
                juuretApp.fileManager.currentFileContent = content
                juuretApp.fileManager.currentFileURL = url
                juuretApp.fileManager.isFileLoaded = true
            }
            
            logInfo(.ui, "✅ File loaded successfully via document picker")
        } catch {
            logError(.ui, "❌ Failed to load file: \(error)")
            await MainActor.run {
                juuretApp.errorMessage = "Failed to load file: \(error.localizedDescription)"
            }
        }
    }
    #endif
    
    // MARK: - Main Interface Views
    
    private var familyExtractionInterface: some View {
        VStack(spacing: 20) {
            // Simplified input section at the top
            familyInputSection
            
            // REMOVED: File info with green icon and filename
            
            // Show processing status if processing
            if juuretApp.isProcessing {
                processingStatusView
            }
            
            // Show error if there's an error
            if let errorMessage = juuretApp.errorMessage {
                errorDisplayView(errorMessage)
            }
            
            // Show family if extracted
            if let family = juuretApp.currentFamily {
                ScrollView {
                    familyDisplaySection(family: family)
                }
            }
        }
    }
    
    private var fileNotLoadedInterface: some View {
        VStack(spacing: 20) {
            // Extract Family section at the top even when no file is loaded
            familyInputSection
            
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No file loaded")
                .font(.genealogyHeadline)
                .foregroundColor(.primary)
            
            Text("Open JuuretKälviällä.txt to begin")
                .font(.genealogyBody)
                .foregroundColor(.secondary)
            
            #if os(iOS)
            Button(action: {
                showingFilePicker = true
            }) {
                Label("Open File", systemImage: "folder.open")
                    .font(.genealogySubheadline)
                    .frame(width: 200, height: 50)
            }
            .buttonStyle(.borderedProminent)
            #elseif os(macOS)
            Button("Open File...") {
                Task {
                    do {
                        // Call FileManager's openFile directly
                        _ = try await juuretApp.fileManager.openFile()
                    } catch {
                        juuretApp.errorMessage = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.genealogySubheadline)
            #endif
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Family Input Section
    
    private var familyInputSection: some View {
        VStack(spacing: 12) {
            // Single line with "Citations for" and input field
            HStack(spacing: 8) {
                Text("Citations for")
                    .font(.genealogyBody)
                    .foregroundColor(.secondary)
                
                TextField("Family ID", text: $familyId)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    #if os(iOS)
                    .autocapitalization(.allCharacters)
                    #endif
                    .disableAutocorrection(true)
                    .onSubmit {
                        if !familyId.isEmpty && juuretApp.isReady {
                            extractFamily()
                        }
                        // Dismiss keyboard on iOS
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                      to: nil, from: nil, for: nil)
                        #endif
                    }
                    .disabled(!juuretApp.isReady || juuretApp.isProcessing)
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
            
            // PROCESSING INDICATOR - Shows while preparing next family
            if let processingId = juuretApp.familyNetworkCache.processingFamilyId {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Preparing \(processingId)...")
                        .font(.genealogyCaption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
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
            
            // REMOVED: The "💡 Click names for citations..." instruction box
            
            familyMembersView(family: family)
        }
    }
    
    private func familyMembersView(family: Family) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Parents section
            if family.father != nil || family.mother != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Parents")
                        .font(.genealogyHeadline)
                        .fontWeight(.semibold)
                    
                    if let father = family.father {
                        personView(person: father, role: .father, family: family)
                    }
                    
                    if let mother = family.mother {
                        personView(person: mother, role: .mother, family: family)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(10)
            }
            
            // Children section
            if !family.children.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Children (\(family.children.count))")
                        .font(.genealogyHeadline)
                        .fontWeight(.semibold)
                    
                    ForEach(family.children) { child in
                        personView(person: child, role: .child, family: family)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.05))
                .cornerRadius(10)
            }
        }
    }
    
    private func personView(person: Person, role: PersonRole, family: Family) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    generateCitation(for: person, in: family)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: role.icon)
                            .foregroundColor(role.color)
                        Text(person.displayName)
                            .font(.genealogySubheadline)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                if let birthDate = person.birthDate {
                    Button(action: {
                        if let query = juuretApp.generateHiskiQuery(for: person, eventType: .birth) {
                            hiskiResult = query
                            showingHiskiResult = true
                        }
                    }) {
                        Label("b. \(birthDate)", systemImage: "calendar")
                            .font(.genealogyCaption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if let deathDate = person.deathDate {
                    Button(action: {
                        if let query = juuretApp.generateHiskiQuery(for: person, eventType: .death) {
                            hiskiResult = query
                            showingHiskiResult = true
                        }
                    }) {
                        Label("d. \(deathDate)", systemImage: "calendar.badge.minus")
                            .font(.genealogyCaption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if let spouse = person.spouse, !spouse.isEmpty {
                HStack(spacing: 8) {
                    Text("m.")
                        .font(.genealogyCaption)
                        .foregroundColor(.secondary)
                    Text(spouse)
                        .font(.genealogyCallout)
                        .foregroundColor(.purple)
                }
            }
        }
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

// MARK: - Supporting Types and Views (unchanged)

#if os(iOS)
struct DocumentPickerView: UIViewControllerRepresentable {
    let urlPicked: (URL) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes = [
            UTType.text,
            UTType.plainText,
            UTType(filenameExtension: "txt") ?? .plainText,
            .data
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.urlPicked(url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
#endif

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
