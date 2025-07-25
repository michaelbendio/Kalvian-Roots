//
//  AISettingsView.swift
//  Kalvian Roots
//
//  AI service configuration interface - FIXED TEXT INPUT
//

import SwiftUI

/**
 * AISettingsView.swift - AI service configuration interface
 *
 * FIXES for text input issues:
 * 1. Removed Form wrapper (known macOS issue)
 * 2. Added explicit focus state
 * 3. Simple VStack layout instead of Form
 * 4. Added keyboard shortcuts
 * 5. Better text field styling
 */

struct AISettingsView: View {
    @Environment(JuuretApp.self) private var app
    @State private var selectedService = "DeepSeek"
    @State private var apiKey = ""
    @State private var showingAPIKey = false
    @State private var isConfiguring = false
    @State private var configurationMessage = ""
    @State private var showingSuccess = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                
                // SECTION 1: Service Selection
                VStack(alignment: .leading, spacing: 15) {
                    Text("AI Service Selection")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Service", selection: $selectedService) {
                            ForEach(app.availableServices, id: \.self) { service in
                                Text(service).tag(service)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedService) { _, newValue in
                            Task {
                                await app.switchAIService(to: newValue)
                                apiKey = ""
                                configurationMessage = ""
                            }
                        }
                        
                        Text("Current service: \(app.currentServiceName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)
                
                // SECTION 2: API Key Input - SIMPLIFIED AND FIXED
                VStack(alignment: .leading, spacing: 15) {
                    Text("API Key Configuration")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter your \(selectedService) API key:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        // FIXED: Simple text field without Form wrapper
                        HStack(spacing: 10) {
                            ZStack {
                                // Background to ensure visibility
                                Rectangle()
                                    .fill(Color(.textBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
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
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.clear)
                            }
                            .frame(minWidth: 300, minHeight: 28)
                            
                            Button(showingAPIKey ? "Hide" : "Show") {
                                showingAPIKey.toggle()
                                // Maintain focus when toggling
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isTextFieldFocused = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        // Quick focus button for debugging
                        HStack {
                            Button("Focus Text Field") {
                                isTextFieldFocused = true
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            
                            Button("Paste from Clipboard") {
                                pasteFromClipboard()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            
                            Spacer()
                        }
                        
                        // Service-specific help
                        Text(getAPIKeyHint(for: selectedService))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Action buttons
                    HStack(spacing: 15) {
                        Button("Save API Key") {
                            Task {
                                await configureService()
                            }
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConfiguring)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        
                        Button("Test Configuration") {
                            Task {
                                await testCurrentConfiguration()
                            }
                        }
                        .disabled(!app.aiParsingService.isConfigured || isConfiguring)
                        .buttonStyle(.bordered)
                        
                        if isConfiguring {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        Spacer()
                    }
                    
                    // Status message
                    if !configurationMessage.isEmpty {
                        Text(configurationMessage)
                            .font(.callout)
                            .foregroundStyle(showingSuccess ? .green : .red)
                            .padding(.vertical, 5)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)
                
                // SECTION 3: Service Status
                VStack(alignment: .leading, spacing: 15) {
                    Text("Service Status")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 8) {
                        ForEach(app.getAIServiceStatus(), id: \.name) { status in
                            HStack {
                                Circle()
                                    .fill(status.configured ? .green : .red)
                                    .frame(width: 10, height: 10)
                                
                                Text(status.name)
                                    .fontWeight(status.name == app.currentServiceName ? .semibold : .regular)
                                
                                if status.name == app.currentServiceName {
                                    Text("(Current)")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                
                                Spacer()
                                
                                Text(status.configured ? "✅ Ready" : "❌ Not Configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)
                
                // SECTION 4: Debug/Testing
                VStack(alignment: .leading, spacing: 15) {
                    Text("Testing & Debug")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("Load Sample API Key") {
                                apiKey = "sk-test-1234567890abcdef1234567890abcdef"
                                configurationMessage = "Sample API key loaded for testing"
                                showingSuccess = false
                                isTextFieldFocused = true
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Clear Field") {
                                apiKey = ""
                                configurationMessage = ""
                                isTextFieldFocused = true
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Clear All Keys") {
                                clearAllAPIKeys()
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.red)
                        }
                        
                        Text("Sample key is for UI testing only. Current field length: \(apiKey.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle("AI Service Configuration")
        .onAppear {
            selectedService = app.currentServiceName
            configurationMessage = ""
            
            // Auto-focus the text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
            
            print("🔧 AISettingsView appeared")
            print("🔧 Current service: \(selectedService)")
            print("🔧 Text field can be focused: \(isTextFieldFocused)")
        }
        .onTapGesture {
            // Tap anywhere to focus text field
            isTextFieldFocused = true
        }
    }
    
    // MARK: - Helper Methods
    
    private func pasteFromClipboard() {
        #if os(macOS)
        if let clipboardString = NSPasteboard.general.string(forType: .string) {
            apiKey = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
            configurationMessage = "Pasted from clipboard (\(apiKey.count) characters)"
            showingSuccess = false
            print("📋 Pasted from clipboard: \(apiKey.count) characters")
        } else {
            configurationMessage = "No text found in clipboard"
            showingSuccess = false
            print("📋 No text in clipboard")
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
        
        print("🔧 Configuring \(selectedService) with key: \(String(trimmedKey.prefix(10)))...")
        
        do {
            await app.configureAIService(apiKey: trimmedKey)
            
            await MainActor.run {
                configurationMessage = "✅ \(selectedService) configured successfully!"
                showingSuccess = true
                apiKey = "" // Clear the field after successful configuration
                print("✅ \(selectedService) configuration successful")
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
                print("❌ \(selectedService) configuration failed: \(error)")
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
                print("✅ \(selectedService) test successful")
            }
            
        } catch {
            await MainActor.run {
                configurationMessage = "❌ Test failed: \(error.localizedDescription)"
                showingSuccess = false
                print("❌ \(selectedService) test failed: \(error)")
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
        
        print("🗑️ All API keys cleared")
    }
    
    private func getAPIKeyHint(for service: String) -> String {
        switch service {
        case "DeepSeek":
            return "Get your API key from https://platform.deepseek.com/api_keys\nFormat: sk-..."
        case "OpenAI GPT-4":
            return "Get your API key from https://platform.openai.com/api-keys\nFormat: sk-..."
        case "Claude":
            return "Get your API key from https://console.anthropic.com/\nFormat: sk-ant-..."
        case "Mock AI":
            return "Mock AI doesn't require an API key - it's for testing only"
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
