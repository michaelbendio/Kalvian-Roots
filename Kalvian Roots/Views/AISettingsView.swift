//
//  AISettingsView.swift
//  Kalvian Roots
//
//  Cross-platform AI service configuration with larger fonts
//

import SwiftUI

/**
 * AISettingsView.swift - Cross-platform AI service configuration
 *
 * Features:
 * - Larger fonts throughout the interface
 * - Platform-aware service selection (MLX on macOS only)
 * - Enhanced debugging for text input
 * - MLX server status monitoring
 */

struct AISettingsView: View {
    @Environment(JuuretApp.self) private var app
    @State private var selectedService = ""
    @State private var apiKey = ""
    @State private var showingAPIKey = false
    @State private var isConfiguring = false
    @State private var configurationMessage = ""
    @State private var showingSuccess = false
    @State private var mlxServerStatus: MLXServerStatus = .notRunning
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                
                // SECTION 1: Platform Info
                platformInfoSection
                
                // SECTION 2: Service Selection
                serviceSelectionSection
                
                // SECTION 3: MLX Status (macOS only)
                #if os(macOS)
                mlxStatusSection
                #endif
                
                // SECTION 4: API Key Configuration
                if !currentServiceIsLocal {
                    apiKeyConfigurationSection
                }
                
                // SECTION 5: Service Status
                serviceStatusSection
                
                // SECTION 6: Debug/Testing
                debugSection
                
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
        }
        .navigationTitle("AI Service Configuration")
        .font(.body) // Larger base font
        .onAppear {
            selectedService = app.currentServiceName
            configurationMessage = ""
            
            Task {
                await updateMLXStatus()
            }
            
            // Auto-focus the text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !currentServiceIsLocal {
                    isTextFieldFocused = true
                }
            }
            
            logInfo(.ui, "🔧 AISettingsView appeared")
            logDebug(.ui, "Current service: \(selectedService)")
            logDebug(.ui, "Platform: \(platformName)")
        }
    }
    
    // MARK: - Platform Info Section
    
    private var platformInfoSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Platform Information")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: platformIcon)
                        .foregroundColor(.blue)
                        .font(.title3)
                    Text("Platform: \(platformName)")
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                Text(platformDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Service Selection Section
    
    private var serviceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI Service Selection")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 15) {
                // Service type sections
                let servicesByType = app.aiParsingService.getServicesByType()
                
                // Local Services (macOS only)
                #if os(macOS)
                if !servicesByType.local.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("🖥️ Local MLX Models")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        ForEach(servicesByType.local, id: \.name) { service in
                            serviceSelectionRow(service)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 5)
                }
                #endif
                
                // Cloud Services
                VStack(alignment: .leading, spacing: 10) {
                    Text("☁️ Cloud API Services")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    ForEach(servicesByType.cloud, id: \.name) { service in
                        serviceSelectionRow(service)
                    }
                }
                
                Text("Current service: \(app.currentServiceName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func serviceSelectionRow(_ service: AIService) -> some View {
        HStack(spacing: 12) {
            // Selection radio button
            Button(action: {
                selectedService = service.name
                Task {
                    await app.switchAIService(to: service.name)
                    apiKey = ""
                    configurationMessage = ""
                    await updateMLXStatus()
                }
            }) {
                Image(systemName: selectedService == service.name ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selectedService == service.name ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(service.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    // Service type badge
                    Text(service.isLocal ? "Local" : "Cloud")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(service.isLocal ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundColor(service.isLocal ? .green : .blue)
                        .cornerRadius(4)
                    
                    // Configuration status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(service.isConfigured ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text(service.isConfigured ? "Ready" : "Not Configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedService = service.name
            Task {
                await app.switchAIService(to: service.name)
                apiKey = ""
                configurationMessage = ""
                await updateMLXStatus()
            }
        }
    }
    
    // MARK: - MLX Status Section (macOS only)
    
    #if os(macOS)
    private var mlxStatusSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("MLX Server Status")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(mlxServerStatus.isAvailable ? .green : .red)
                        .frame(width: 12, height: 12)
                    
                    Text("MLX Server: \(mlxServerStatus.description)")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button("Refresh") {
                        Task {
                            await updateMLXStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if !mlxServerStatus.isAvailable {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To use local MLX models:")
                            .font(.callout)
                            .fontWeight(.medium)
                        
                        Text("1. Run the MLX setup script")
                        Text("2. Start the MLX server: ~/.kalvian_roots_mlx/start_mlx_server.sh")
                        Text("3. Refresh this status")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
                }
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    #endif
    
    // MARK: - API Key Configuration Section
    
    private var apiKeyConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("API Key Configuration")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Enter your \(selectedService) API key:")
                    .font(.body)
                    .fontWeight(.medium)
                
                // Enhanced text field with larger fonts
                HStack(spacing: 12) {
                    ZStack {
                        Rectangle()
                            .fill(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separatorColor), lineWidth: 1)
                            )
                        
                        Group {
                            if showingAPIKey {
                                TextField("sk-...", text: $apiKey)
                                    .focused($isTextFieldFocused)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                                    .focused($isTextFieldFocused)
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.clear)
                    }
                    .frame(minWidth: 350, minHeight: 36)
                    
                    Button(showingAPIKey ? "Hide" : "Show") {
                        showingAPIKey.toggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isTextFieldFocused = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                
                // Helper buttons
                HStack(spacing: 15) {
                    Button("Focus Field") {
                        isTextFieldFocused = true
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .foregroundStyle(.blue)
                    
                    Button("Paste") {
                        pasteFromClipboard()
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .foregroundStyle(.blue)
                    
                    Spacer()
                }
                
                // Service-specific help with larger text
                Text(getAPIKeyHint(for: selectedService))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Action buttons with larger sizes
            HStack(spacing: 20) {
                Button("Save API Key") {
                    Task {
                        await configureService()
                    }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConfiguring)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: .command)
                
                Button("Test Configuration") {
                    Task {
                        await testCurrentConfiguration()
                    }
                }
                .disabled(!app.aiParsingService.isConfigured || isConfiguring)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                if isConfiguring {
                    ProgressView()
                        .scaleEffect(1.0)
                }
                
                Spacer()
            }
            
            // Status message with larger text
            if !configurationMessage.isEmpty {
                Text(configurationMessage)
                    .font(.body)
                    .foregroundStyle(showingSuccess ? .green : .red)
                    .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Service Status Section
    
    private var serviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Service Status")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(app.getAIServiceStatus(), id: \.name) { status in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(status.configured ? .green : .red)
                            .frame(width: 12, height: 12)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(status.name)
                                    .font(.body)
                                    .fontWeight(status.name == app.currentServiceName ? .semibold : .regular)
                                
                                if status.name == app.currentServiceName {
                                    Text("(Current)")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                            
                            HStack {
                                Text(status.isLocal ? "🖥️ Local" : "☁️ Cloud")
                                    .font(.caption)
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(status.configured ? "✅ Ready" : "❌ Not Configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Debug Section
    
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Testing & Debug")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 15) {
                    Button("Load Sample API Key") {
                        apiKey = "sk-test-1234567890abcdef1234567890abcdef"
                        configurationMessage = "Sample API key loaded for testing"
                        showingSuccess = false
                        isTextFieldFocused = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button("Clear Field") {
                        apiKey = ""
                        configurationMessage = ""
                        isTextFieldFocused = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button("Clear All Keys") {
                        clearAllAPIKeys()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .foregroundStyle(.red)
                }
                
                Text("Sample key is for UI testing only. Current field length: \(apiKey.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                #if os(macOS)
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("MLX Server Commands")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start: ~/.kalvian_roots_mlx/start_mlx_server.sh")
                        Text("Health: curl http://127.0.0.1:11434/health")
                        Text("Models: curl http://127.0.0.1:11434/models")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                #endif
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    
    private var currentServiceIsLocal: Bool {
        app.availableServices.first { $0 == selectedService }?.contains("Local") ?? false
    }
    
    private var platformName: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "Unknown"
        #endif
    }
    
    private var platformIcon: String {
        #if os(macOS)
        return "desktopcomputer"
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #elseif os(visionOS)
        return "visionpro"
        #else
        return "questionmark.circle"
        #endif
    }
    
    private var platformDescription: String {
        #if os(macOS)
        return "Full AI services available including local MLX models for privacy and speed. MLX models require setup but provide unlimited usage without API costs."
        #elseif os(iOS)
        return "Cloud AI services available. DeepSeek provides excellent genealogical parsing at low cost. MLX local models are not supported on mobile devices."
        #elseif os(visionOS)
        return "Cloud AI services available. Optimized for spatial computing interface with gesture controls."
        #else
        return "Platform-specific AI services will be configured automatically."
        #endif
    }
    
    // MARK: - Helper Methods
    
    private func updateMLXStatus() async {
        #if os(macOS)
        mlxServerStatus = await app.aiParsingService.checkMLXServerStatus()
        logDebug(.ai, "MLX server status updated: \(mlxServerStatus.description)")
        #endif
    }
    
    private func pasteFromClipboard() {
        #if os(macOS)
        if let clipboardString = NSPasteboard.general.string(forType: .string) {
            apiKey = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
            configurationMessage = "Pasted from clipboard (\(apiKey.count) characters)"
            showingSuccess = false
            logInfo(.ui, "📋 Pasted from clipboard: \(apiKey.count) characters")
        } else {
            configurationMessage = "No text found in clipboard"
            showingSuccess = false
            logInfo(.ui, "📋 No text in clipboard")
        }
        #else
        // iOS clipboard access
        if let clipboardString = UIPasteboard.general.string {
            apiKey = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
            configurationMessage = "Pasted from clipboard (\(apiKey.count) characters)"
            showingSuccess = false
            logInfo(.ui, "📋 Pasted from clipboard: \(apiKey.count) characters")
        } else {
            configurationMessage = "No text found in clipboard"
            showingSuccess = false
            logInfo(.ui, "📋 No text in clipboard")
        }
        #endif
    }
    
    private func configureService() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            configurationMessage = "Please enter an API key"
            showingSuccess = false
            return
        }
        
        isConfiguring = true
        configurationMessage = "Configuring \(selectedService)..."
        showingSuccess = false
        
        logInfo(.ai, "🔧 Configuring \(selectedService) with key: \(String(trimmedKey.prefix(10)))...")
        
        do {
            await app.configureAIService(apiKey: trimmedKey)
            
            await MainActor.run {
                configurationMessage = "✅ \(selectedService) configured successfully!"
                showingSuccess = true
                apiKey = "" // Clear the field after successful configuration
                logInfo(.ai, "✅ \(selectedService) configuration successful")
            }
            
            // Auto-clear success message after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if configurationMessage.contains("successfully") {
                    configurationMessage = ""
                }
            }
            
        } catch {
            await MainActor.run {
                configurationMessage = "❌ Configuration failed: \(error.localizedDescription)"
                showingSuccess = false
                logError(.ai, "❌ \(selectedService) configuration failed: \(error)")
            }
        }
        
        await MainActor.run {
            isConfiguring = false
        }
    }
    
    private func testCurrentConfiguration() async {
        guard app.aiParsingService.isConfigured else {
            configurationMessage = "❌ Service not configured"
            showingSuccess = false
            return
        }
        
        isConfiguring = true
        configurationMessage = "Testing \(selectedService) configuration..."
        showingSuccess = false
        
        do {
            // Try to parse a simple test family
            let testFamily = try await app.aiParsingService.parseFamily(
                familyId: "TEST 1",
                familyText: "TEST 1, page 1\n★ 01.01.1700 Test Matinp.\n★ 01.01.1705 Example Juhont.\nLapset\n★ 01.01.1725 Child"
            )
            
            await MainActor.run {
                configurationMessage = "✅ \(selectedService) test successful! Parsed family: \(testFamily.familyId)"
                showingSuccess = true
                logInfo(.ai, "✅ \(selectedService) test successful")
            }
            
        } catch {
            await MainActor.run {
                configurationMessage = "❌ Test failed: \(error.localizedDescription)"
                showingSuccess = false
                logError(.ai, "❌ \(selectedService) test failed: \(error)")
            }
        }
        
        await MainActor.run {
            isConfiguring = false
        }
    }
    
    private func clearAllAPIKeys() {
        for serviceName in app.availableServices {
            UserDefaults.standard.removeObject(forKey: "AIService_\(serviceName)_APIKey")
        }
        
        configurationMessage = "All API keys cleared"
        showingSuccess = false
        apiKey = ""
        
        logInfo(.ui, "🗑️ All API keys cleared")
    }
    
    private func getAPIKeyHint(for service: String) -> String {
        switch service {
        case let s where s.contains("DeepSeek"):
            return "Get your API key from https://platform.deepseek.com/api_keys\nFormat: sk-..."
        case let s where s.contains("Claude"):
            return "Get your API key from https://console.anthropic.com/\nFormat: sk-ant-..."
        case let s where s.contains("Mock"):
            return "Mock AI doesn't require an API key - it's for testing only"
        case let s where s.contains("Local MLX"):
            return "Local MLX models don't require API keys. Ensure the MLX server is running."
        default:
            return "Enter your API key for \(service)"
        }
    }
}

// MARK: - Preview
#Preview {
    AISettingsView()
        .environment(JuuretApp())
}
