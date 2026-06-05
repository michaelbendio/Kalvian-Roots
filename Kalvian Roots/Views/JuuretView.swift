//
//  JuuretView.swift - UPDATED with AI Ready Indicator
//  Kalvian Roots
//
//  Main family display view with green dot showing when AI is ready
//

import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct JuuretView: View {
    @Environment(JuuretApp.self) private var juuretApp
    @State private var showingCitation = false
    @State private var citationText = ""
    @State private var showingHiskiResult = false
    @State private var hiskiResult = ""
    @State private var showingFatalError = false
    @State private var shouldCloseHiskiWindows = false
    @State private var showingHiskiWorkbench = false
    
    var body: some View {
        VStack(spacing: 0) {
            if juuretApp.fileManager.isFileLoaded {
                // Navigation bar at top
                NavigationBarView(
                    prefetchManager: juuretApp.prefetchManager,
                    onShowHiskiWorkbench: {
                        showingHiskiWorkbench = true
                    }
                )
                
                // Main content area - CHECK FOR PENDING ID FIRST
                if let pendingId = juuretApp.pendingFamilyId {
                    // LOADING STATE - Show while extracting
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading \(pendingId)...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: "fefdf8"))
                    
                } else if let family = juuretApp.currentFamily {
                    // FAMILY LOADED - Show content
                    FamilyContentView(
                        family: family,
                        showsComparisonSourceMarkers: !showingCitation,
                        onShowCitation: { citation in
                            citationText = citation
                            showingCitation = true
                        },
                        onShowHiski: { result in
                            hiskiResult = result
                            showingHiskiResult = true
                        }
                    )
                    .id(family.familyId)
                } else {
                    // NO FAMILY - Show empty state
                    emptyStateView
                }
            } else {
                Color.clear
            }
        }
        .navigationTitle("Kalvian Roots")
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // AI READY INDICATOR - Green dot when AI is ready
                Circle()
                    .fill(isAIReady ? Color.green : Color.clear)
                    .frame(width: 6, height: 6)
                    .opacity(isAIReady ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.3), value: isAIReady)

                CachedFamiliesMenu()
            }
        }
        #elseif os(iOS) || os(visionOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    // AI READY INDICATOR - Green dot when AI is ready
                    Circle()
                        .fill(isAIReady ? Color.green : Color.clear)
                        .frame(width: 6, height: 6)
                        .opacity(isAIReady ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.3), value: isAIReady)

                    CachedFamiliesMenu()
                }
            }
        }
        .setupHiskiSafariHost()
        #endif
        
        // Citation alert
        .alert("Citation", isPresented: $showingCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(citationText)
                shouldCloseHiskiWindows = true
            }
            Button("OK", role: .cancel) {
                // Don't close windows for regular citations
            }
        } message: {
            Text(citationText)
        }
        .onChange(of: showingCitation) { _, newValue in
            if !newValue && shouldCloseHiskiWindows {
                #if os(macOS)
                closeAllHiskiWindows()
                #endif
                shouldCloseHiskiWindows = false
            }
        }
        
        // Hiski result alert
        .alert("Hiski Query", isPresented: $showingHiskiResult) {
            // Only show Copy button if result is a valid URL
            if hiskiResult.starts(with: "https://") {
                Button("Copy to Clipboard") {
                    copyToClipboard(hiskiResult)
                }
            }
            #if os(macOS)
            // Only show Open in Browser if result is a valid URL
            if hiskiResult.starts(with: "https://") {
                Button("Open in Browser") {
                    openHiskiInBrowser(hiskiResult)
                }
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text(hiskiResult)
        }
        .sheet(isPresented: $showingHiskiWorkbench) {
            if let family = juuretApp.currentFamily {
                ManualHiskiWorkbenchView(
                    family: family,
                    initialFields: HiskiService.defaultManualBirthSearchFields(for: family)
                )
                .environment(juuretApp)
            }
        }
    }
    
    // MARK: - AI Ready Indicator Logic
    
    private var isAIReady: Bool {
        juuretApp.aiParsingService.isConfigured
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 72))
                .foregroundColor(.gray)
            
            Text("No Family Selected")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("Enter a family ID in the navigation bar or select from cached families")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "fefdf8"))
    }
    
    // MARK: - Helper Methods
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
    
    #if os(macOS)
    private func openHiskiInBrowser(_ url: String) {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func closeAllHiskiWindows() {
        // Close all Safari windows with hiski.genealogia.fi
        let script = """
        tell application "Safari"
            set windowList to every window
            repeat with aWindow in windowList
                try
                    set tabList to every tab of aWindow
                    repeat with aTab in tabList
                        if URL of aTab contains "hiski.genealogia.fi" then
                            close aTab
                        end if
                    end repeat
                end try
            end repeat
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                logWarn(.app, "Failed to close Hiski windows: \(error)")
            }
        }
    }
    #endif
}

private struct ManualHiskiWorkbenchView: View {
    @Environment(JuuretApp.self) private var juuretApp
    @Environment(\.dismiss) private var dismiss

    let family: Family
    @State private var fields: HiskiService.ManualBirthSearchFields
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isRefreshingFamily = false

    init(family: Family, initialFields: HiskiService.ManualBirthSearchFields) {
        self.family = family
        _fields = State(initialValue: initialFields)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HisKi Births")
                        .font(.title2.weight(.semibold))
                    Text(family.familyId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Family") {
                    refreshFamily()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRefreshingFamily)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Form {
                Section("Search") {
                    TextField("Child first name", text: $fields.childFirstName)
                    TextField("Start year", text: $fields.startYear)
                    TextField("End year", text: $fields.endYear)
                    TextField("Farm name", text: $fields.villageFarm)
                    TextField("Max events", text: $fields.maxEvents)
                }

                Section("Father") {
                    TextField("First name", text: $fields.fatherFirstName)
                    TextField("Patronymic", text: $fields.fatherPatronymic)
                    TextField("Last name", text: $fields.fatherLastName)
                }

                Section("Mother") {
                    TextField("First name", text: $fields.motherFirstName)
                    TextField("Patronymic", text: $fields.motherPatronymic)
                    TextField("Last name", text: $fields.motherLastName)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button {
                    submitHiskiSearch()
                } label: {
                    Label("Submit", systemImage: "safari")
                }

                Button("Family") {
                    refreshFamily()
                }
                .disabled(isRefreshingFamily)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 560)
    }

    private func submitHiskiSearch() {
        do {
            let url = try juuretApp.manualHiskiBirthSearchURL(fields: fields)
            openURL(url)
            statusMessage = "HisKi search opened."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshFamily() {
        isRefreshingFamily = true
        statusMessage = "Loading HisKi results..."
        errorMessage = nil

        Task {
            do {
                let rowCount = try await juuretApp.refreshCurrentFamilyFromManualHiski(fields: fields)
                statusMessage = "\(rowCount) HisKi birth result \(rowCount == 1 ? "row" : "rows") used."
                isRefreshingFamily = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRefreshingFamily = false
            }
        }
    }

    private func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Preview

#Preview {
    JuuretView()
        .environment(JuuretApp())
}
