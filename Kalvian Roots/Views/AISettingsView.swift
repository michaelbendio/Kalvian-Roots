//
//  AISettingsView.swift
//  Kalvian Roots
//
//  Enhanced AI service management with proper MLX handling
//

import SwiftUI

struct AISettingsView: View {
    @Environment(JuuretApp.self) private var juuretApp
    @State private var showingAPIKeyInput = false
    @State private var tempAPIKey = ""
    @State private var selectedServiceForConfig = ""
    @State private var isCheckingMLXStatus = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current Service Display
                currentServiceSection
                
                // Available Services
                availableServicesSection
                
                #if os(macOS)
                // MLX Status (only on macOS)
                mlxStatusSection
                #endif
            }
            .padding()
        }
        .navigationTitle("AI Settings")
        .sheet(isPresented: $showingAPIKeyInput) {
            apiKeyInputSheet
        }
    }
    
    // MARK: - Current Service Section
    
    private var currentServiceSection: some View {
        GroupBox("Current Service") {
            HStack {
                Image(systemName: serviceIcon(for: juuretApp.currentServiceName))
                    .foregroundColor(serviceTypeColor(for: juuretApp.currentServiceName))
                
                VStack(alignment: .leading) {
                    Text(juuretApp.currentServiceName)
                        .font(.genealogyHeadline)
                    
                    HStack {
                        Text(serviceTypeText(for: juuretApp.currentServiceName))
                            .font(.genealogyCaption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(serviceTypeColor(for: juuretApp.currentServiceName).opacity(0.2))
                            .cornerRadius(4)
                        
                        if isServiceConfigured(juuretApp.currentServiceName) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.genealogyCaption)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Available Services Section
    
    private var availableServicesSection: some View {
        GroupBox("Available Services") {
            LazyVStack(spacing: 8) {
                ForEach(juuretApp.availableServices, id: \.self) { serviceName in
                    serviceRow(serviceName: serviceName)
                }
            }
        }
    }
    
    private func serviceRow(serviceName: String) -> some View {
        HStack {
            // Service icon and info
            HStack(spacing: 12) {
                Image(systemName: serviceIcon(for: serviceName))
                    .foregroundColor(serviceTypeColor(for: serviceName))
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(serviceName)
                        .font(.genealogySubheadline)
                    
                    Text(serviceTypeText(for: serviceName))
                        .font(.genealogyCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Status indicators
            HStack(spacing: 8) {
                // Configuration status
                if isServiceConfigured(serviceName) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.genealogyCaption)
                } else if !serviceName.contains("MLX") {
                    // Only show "needs config" for cloud services
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.genealogyCaption)
                }
                
                // Action buttons
                if serviceName == juuretApp.currentServiceName {
                    Text("Current")
                        .font(.genealogyCaption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    actionButtons(for: serviceName)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func actionButtons(for serviceName: String) -> some View {
        HStack(spacing: 4) {
            // Configure button (only for cloud services that need API keys)
            if !serviceName.contains("MLX") && !isServiceConfigured(serviceName) {
                Button("Configure") {
                    configureService(serviceName)
                }
                .buttonStyle(.bordered)
                .font(.genealogyCaption)
                .foregroundColor(.orange)
            }
            
            // Switch button
            Button("Switch") {
                switchToService(serviceName)
            }
            .buttonStyle(.borderedProminent)
            .font(.genealogyCaption)
        }
    }
    
    // MARK: - API Key Input Sheet
    
    private var apiKeyInputSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Configure \(selectedServiceForConfig)")
                    .font(.genealogyTitle)
                
                Text("Enter your API key for this service:")
                    .font(.genealogyBody)
                    .foregroundColor(.secondary)
                
                SecureField("API Key", text: $tempAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.genealogyMonospaceSmall)
                
                Button("Save") {
                    saveAPIKey()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tempAPIKey.isEmpty)
                
                Spacer()
            }
            .padding()
            .navigationTitle("API Key")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
#if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAPIKeyInput = false
                        tempAPIKey = ""
                    }
                }
            }
#else
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingAPIKeyInput = false
                        tempAPIKey = ""
                    }
                }
            }
#endif
        }
    }
    
    // MARK: - MLX Status Section
    
    #if os(macOS)
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
                
                Text("Local AI processing - no API costs, enhanced privacy")
                    .font(.genealogyCallout)
                    .foregroundColor(.secondary)
                
                // MLX Services
                let mlxServices = juuretApp.availableServices.filter { $0.contains("MLX") }
                if !mlxServices.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available Models:")
                            .font(.genealogyCaption)
                            .foregroundColor(.secondary)
                        
                        ForEach(mlxServices, id: \.self) { service in
                            HStack {
                                Text("• \(service)")
                                    .font(.genealogyCaption)
                                    .foregroundColor(.primary)
                                
                                if service == juuretApp.currentServiceName {
                                    Text("Current")
                                        .font(.genealogyCaption)
                                        .foregroundColor(.blue)
                                }
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Text("No MLX models available")
                        .font(.genealogyCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    #endif
    
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
        // FIXED: MLX services are always "configured" if available
        if serviceName.contains("MLX") {
            return true
        }
        
        // For cloud services, check if we have a saved API key
        return UserDefaults.standard.string(forKey: "AIService_\(serviceName)_APIKey") != nil
    }
    
    private func configureService(_ serviceName: String) {
        // FIXED: Only allow configuration for non-MLX services
        guard !serviceName.contains("MLX") else {
            return // MLX services don't need configuration
        }
        
        selectedServiceForConfig = serviceName
        tempAPIKey = ""
        showingAPIKeyInput = true
    }
    
    private func switchToService(_ serviceName: String) {
        Task {
            do {
                // FIXED: Direct switch without trying to configure MLX services
                try await juuretApp.switchAIService(to: serviceName)
            } catch {
                // Handle switching errors gracefully
                print("Failed to switch AI service: \(error)")
                // In a production app, you might want to show an alert here
            }
        }
    }
    
    private func saveAPIKey() {
        Task {
            do {
                try await juuretApp.configureAIService(apiKey: tempAPIKey)
                showingAPIKeyInput = false
                tempAPIKey = ""
            } catch {
                // Handle configuration errors gracefully
                print("Failed to configure API key: \(error)")
                // In a production app, you might want to show an alert here
            }
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
    AISettingsView()
        .environment(JuuretApp())
}
