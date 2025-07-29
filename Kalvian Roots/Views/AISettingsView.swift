//
//  AISettingsView.swift
//  Kalvian Roots
//
//  AI service configuration view compatible with actual codebase
//

import SwiftUI

/**
 * AI Settings view that works with your actual MLXService and AIParsingService
 */
struct AISettingsView: View {
    @Bindable var juuretApp: JuuretApp
    @State private var showingAPIKeyInput = false
    @State private var tempAPIKey = ""
    @State private var selectedServiceForConfig: String = ""
    @State private var isCheckingMLXStatus = false
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Services")
                        .font(.genealogyTitle)
                    
                    Text("Configure AI services for family parsing")
                        .font(.genealogyBody)
                        .foregroundColor(.secondary)
                }
                
                // Current Service Status
                currentServiceSection
                
                // Available Services
                availableServicesSection
                
                // MLX Status (if available)
                if MLXService.isAvailable() {
                    mlxStatusSection
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("AI Configuration")
            .sheet(isPresented: $showingAPIKeyInput) {
                apiKeyInputSheet
            }
        }
    }
    
    // MARK: - Current Service Section
    
    private var currentServiceSection: some View {
        GroupBox("Current Service") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: juuretApp.aiParsingService.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(juuretApp.aiParsingService.isConfigured ? .green : .orange)
                    
                    Text(juuretApp.currentServiceName)
                        .font(.genealogyHeadline)
                    
                    Spacer()
                    
                    Text(serviceTypeText(for: juuretApp.currentServiceName))
                        .font(.genealogyCaption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(serviceTypeColor(for: juuretApp.currentServiceName).opacity(0.2))
                        .cornerRadius(4)
                }
                
                if !juuretApp.aiParsingService.isConfigured {
                    Text("Service needs configuration")
                        .font(.genealogyCallout)
                        .foregroundColor(.orange)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Available Services Section
    
    private var availableServicesSection: some View {
        GroupBox("Available Services") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(juuretApp.availableServices, id: \.self) { serviceName in
                    serviceRow(serviceName: serviceName)
                }
            }
            .padding()
        }
    }
    
    private func serviceRow(serviceName: String) -> some View {
        HStack {
            // Service icon
            Image(systemName: serviceIcon(for: serviceName))
                .foregroundColor(serviceTypeColor(for: serviceName))
                .frame(width: 20)
            
            // Service name
            VStack(alignment: .leading, spacing: 2) {
                Text(serviceName)
                    .font(.genealogyBody)
                
                Text(serviceTypeText(for: serviceName))
                    .font(.genealogyCaption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Configuration status
            if isServiceConfigured(serviceName) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Configure") {
                    configureService(serviceName)
                }
                .buttonStyle(.bordered)
                .font(.genealogyCaption)
            }
            
            // Switch button
            if serviceName != juuretApp.currentServiceName {
                Button("Switch") {
                    switchToService(serviceName)
                }
                .buttonStyle(.borderedProminent)
                .font(.genealogyCaption)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - MLX Status Section
    
    private var mlxStatusSection: some View {
        GroupBox("MLX Local AI") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu.fill")
                        .foregroundColor(.blue)
                    
                    Text("Apple Silicon MLX")
                        .font(.genealogyHeadline)
                    
                    Spacer()
                    
                    if isCheckingMLXStatus {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Check Status") {
                            checkMLXStatus()
                        }
                        .buttonStyle(.bordered)
                        .font(.genealogyCaption)
                    }
                }
                
                Text("Local AI processing on Apple Silicon - no API costs, enhanced privacy")
                    .font(.genealogyCallout)
                    .foregroundColor(.secondary)
                
                // MLX Services
                let mlxServices = juuretApp.availableServices.filter { $0.contains("MLX") }
                if !mlxServices.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available Models:")
                            .font(.genealogyCallout)
                            .fontWeight(.medium)
                        
                        ForEach(mlxServices, id: \.self) { service in
                            Text("• \(service)")
                                .font(.genealogyCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - API Key Input Sheet
    
    private var apiKeyInputSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Configure \(selectedServiceForConfig)")
                    .font(.genealogyTitle)
                
                Text("Enter your API key for \(selectedServiceForConfig)")
                    .font(.genealogyBody)
                    .foregroundColor(.secondary)
                
                SecureField("API Key", text: $tempAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.genealogyMonospace)
                
                if !tempAPIKey.isEmpty {
                    Text("Key length: \(tempAPIKey.count) characters")
                        .font(.genealogyCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("API Configuration")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAPIKeyInput = false
                        tempAPIKey = ""
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAPIKey()
                    }
                    .disabled(tempAPIKey.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func serviceTypeText(for serviceName: String) -> String {
        if serviceName.contains("MLX") {
            return "Local"
        } else if serviceName.contains("Mock") {
            return "Test"
        } else {
            return "Cloud"
        }
    }
    
    private func serviceTypeColor(for serviceName: String) -> Color {
        if serviceName.contains("MLX") {
            return .blue
        } else if serviceName.contains("Mock") {
            return .purple
        } else {
            return .green
        }
    }
    
    private func serviceIcon(for serviceName: String) -> String {
        if serviceName.contains("MLX") {
            return "cpu.fill"
        } else if serviceName.contains("Mock") {
            return "testtube.2"
        } else {
            return "cloud.fill"
        }
    }
    
    private func isServiceConfigured(_ serviceName: String) -> Bool {
        // For MLX services, they're always "configured" if available
        if serviceName.contains("MLX") {
            return true
        }
        
        // For cloud services, check if we have a saved API key
        return UserDefaults.standard.string(forKey: "AIService_\(serviceName)_APIKey") != nil
    }
    
    private func configureService(_ serviceName: String) {
        selectedServiceForConfig = serviceName
        tempAPIKey = ""
        showingAPIKeyInput = true
    }
    
    private func switchToService(_ serviceName: String) {
        Task {
            do {
                try await juuretApp.switchAIService(to: serviceName)
            } catch {
                print("Failed to switch AI service: \(error)")
            }
        }
    }
    
    private func saveAPIKey() {
        Task {
            await juuretApp.configureAIService(apiKey: tempAPIKey)
            showingAPIKeyInput = false
            tempAPIKey = ""
        }
    }
    
    private func checkMLXStatus() {
        isCheckingMLXStatus = true
        
        Task {
            // Give it a moment to show the progress indicator
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                isCheckingMLXStatus = false
                // You could add more detailed status checking here
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AISettingsView(juuretApp: JuuretApp())
}

