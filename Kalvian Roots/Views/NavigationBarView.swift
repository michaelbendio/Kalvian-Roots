//
//  NavigationBarView.swift
//  Kalvian Roots
//
//  Browser-style navigation bar for family browsing
//

import SwiftUI

struct NavigationBarView: View {
    @Environment(JuuretApp.self) private var juuretApp
    @State private var familyIdInput: String = ""
    @State private var showingClanBrowser: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Back button - navigates to PREVIOUS FAMILY IN FILE
            Button(action: {
                juuretApp.navigateToPreviousFamily()  // Changed from navigateBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(NavigationButtonStyle())
            .disabled(!juuretApp.canNavigateToPreviousFamily)  // Changed from canNavigateBack

            // Forward button - navigates to NEXT FAMILY IN FILE
            Button(action: {
                juuretApp.navigateToNextFamily()  // Changed from navigateForward()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(NavigationButtonStyle())
            .disabled(!juuretApp.canNavigateToNextFamily)  // Changed from canNavigateForward
            // Home button
            Button(action: {
                juuretApp.navigateHome()
            }) {
                HStack(spacing: 4) {
                    Text("🏠")
                        .font(.system(size: 14))
                    Text("Home")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .buttonStyle(NavigationButtonStyle())
            .disabled(!juuretApp.canNavigateHome)
            
            // Reload/Load button
            Button(action: {
                if let familyId = juuretApp.currentFamily?.familyId {
                    Task {
                        await juuretApp.extractFamily(familyId: familyId)
                    }
                }
            }) {
                Text(isCurrentFamilyCached ? "Reload" : "Load")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(NavigationButtonStyle())
            .disabled(juuretApp.currentFamily == nil)
            
            // Family ID input with dropdown
            // Family ID input with dropdown
            HStack(spacing: 4) {
                TextField("Enter family ID...", text: $familyIdInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(6)
                    .onSubmit {
                        navigateToInputFamily()
                    }
                    // FIXED: Watch BOTH pendingFamilyId and currentFamily
                    .onChange(of: juuretApp.pendingFamilyId) { oldValue, newValue in
                        if let pendingId = newValue {
                            familyIdInput = pendingId
                        }
                    }
                    .onChange(of: juuretApp.currentFamily?.familyId) { oldValue, newValue in
                        // Only update if there's no pending ID
                        if juuretApp.pendingFamilyId == nil, let newId = newValue {
                            familyIdInput = newId
                        }
                    }
                    .onAppear {
                        // Show pending ID if set, otherwise current family
                        if let pendingId = juuretApp.pendingFamilyId {
                            familyIdInput = pendingId
                        } else if let currentId = juuretApp.currentFamily?.familyId {
                            familyIdInput = currentId
                        }
                    }
               }
            
            .frame(maxWidth: .infinity)
            
            // PDF toggle button
            Button(action: {
                juuretApp.showPDFMode.toggle()
            }) {
                Text("PDF")
                    .font(.system(size: 14, weight: juuretApp.showPDFMode ? .semibold : .medium))
            }
            .buttonStyle(PDFToggleButtonStyle(isActive: juuretApp.showPDFMode))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .sheet(isPresented: $showingClanBrowser) {
            ClanBrowserView(isPresented: $showingClanBrowser)
        }
    }
    
    // MARK: - Helpers
    
    private var isCurrentFamilyCached: Bool {
        guard let familyId = juuretApp.currentFamily?.familyId else { return false }
        return juuretApp.familyNetworkCache.getCachedNetwork(familyId: familyId) != nil
    }
    
    private func navigateToInputFamily() {
        let trimmedId = familyIdInput.trimmingCharacters(in: .whitespaces)
        guard !trimmedId.isEmpty else { return }
        
        // Navigate with history update (sets as home)
        juuretApp.navigateToFamily(trimmedId, updateHistory: true)
    }
}

// MARK: - Button Styles

struct NavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.3 : 0.2)
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
}

struct PDFToggleButtonStyle: ButtonStyle {
    let isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isActive ? Color(hex: "667eea") : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isActive ? Color.white.opacity(0.95) : Color.white.opacity(0.2)
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationBarView()
        .environment(JuuretApp())
}
