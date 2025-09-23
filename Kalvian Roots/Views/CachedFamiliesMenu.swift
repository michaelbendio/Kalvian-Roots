//
//  CachedFamiliesMenu.swift
//  Kalvian Roots
//
//  Cache management menu with search capability
//
//  Created by Michael Bendio on 9/23/25.
//

import SwiftUI

struct CachedFamiliesMenu: View {
    @Environment(JuuretApp.self) private var app
    @State private var searchText = ""
    @State private var showingDeleteConfirmation = false
    @State private var familyToDelete: String?
    @State private var showingClearAllConfirmation = false
    
    var allCachedFamilyIds: [String] {
        app.familyNetworkCache.getAllCachedFamilyIds()
    }
    
    // Filtered families based on search
    var filteredFamilyIds: [String] {
        if searchText.isEmpty {
            return allCachedFamilyIds
        } else {
            return allCachedFamilyIds.filter { familyId in
                familyId.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // Limit display to prevent menu from becoming too tall
    var displayedFamilyIds: ArraySlice<String> {
        filteredFamilyIds.prefix(20)  // Show max 20 at a time
    }
    
    var hasMore: Bool {
        filteredFamilyIds.count > 20
    }
    
    var body: some View {
        Menu {
            if allCachedFamilyIds.isEmpty {
                Text("No cached families")
                    .foregroundStyle(.secondary)
            } else {
                // Search field at the top of menu
                if allCachedFamilyIds.count > 5 {  // Only show search if more than 5 families
                    SearchFieldMenuItem(text: $searchText)
                    
                    Divider()
                }
                
                // Show filtered results
                if filteredFamilyIds.isEmpty && !searchText.isEmpty {
                    Text("No families matching '\(searchText)'")
                        .foregroundStyle(.secondary)
                } else {
                    // Display families
                    ForEach(Array(displayedFamilyIds), id: \.self) { familyId in
                        FamilyMenuItem(
                            familyId: familyId,
                            isCurrentFamily: app.currentFamily?.familyId == familyId,
                            onLoad: {
                                Task {
                                    await app.extractFamily(familyId: familyId)
                                }
                            },
                            onDelete: {
                                familyToDelete = familyId
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                    
                    // Show if there are more results
                    if hasMore {
                        Divider()
                        Text("+ \(filteredFamilyIds.count - 20) more families")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Refine search to see more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // Cache management section
                Menu("Manage Cache") {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("\(allCachedFamilyIds.count) families cached")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showingClearAllConfirmation = true
                    } label: {
                        Label("Clear All Cache", systemImage: "trash.fill")
                    }
                }
            }
        } label: {
            Label("Cached Families (\(allCachedFamilyIds.count))", systemImage: "internaldrive")
        }
        .confirmationDialog(
            "Delete from Cache",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(familyToDelete ?? "")", role: .destructive) {
                if let familyId = familyToDelete {
                    app.familyNetworkCache.deleteCachedFamily(familyId: familyId)
                    familyToDelete = nil
                    // Clear search if we just deleted the last result
                    if filteredFamilyIds.count == 1 {
                        searchText = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                familyToDelete = nil
            }
        } message: {
            Text("Remove \(familyToDelete ?? "") from cache. You can regenerate it later with updated citations.")
        }
        .confirmationDialog(
            "Clear All Cache",
            isPresented: $showingClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                app.familyNetworkCache.clearCache()
                searchText = ""  // Reset search
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all \(allCachedFamilyIds.count) families from the cache.")
        }
    }
}

// MARK: - Search Field Component

/// Custom search field that works in a menu
private struct SearchFieldMenuItem: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search families...", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onAppear {
                    // Auto-focus the search field when menu opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFocused = true
                    }
                }
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Family Menu Item Component

/// Individual family menu item with submenu
private struct FamilyMenuItem: View {
    let familyId: String
    let isCurrentFamily: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    @Environment(JuuretApp.self) private var app
    
    var body: some View {
        Menu {
            Button {
                onLoad()
            } label: {
                Label("Load", systemImage: "doc.text")
            }
            
            Button {
                Task {
                    await app.regenerateCachedFamily(familyId: familyId)
                }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .help("Delete and re-extract with updated citations")
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete from Cache", systemImage: "trash")
            }
            
            // Show cache info
            if let info = app.familyNetworkCache.getCachedFamilyInfo(familyId: familyId) {
                Divider()
                
                Text("Cached: \(info.cachedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                
                Text("Extraction: \(String(format: "%.1f", info.extractionTime))s")
                    .font(.caption)
            }
        } label: {
            HStack {
                Text(familyId)
                    .fontWeight(isCurrentFamily ? .semibold : .regular)
                
                Spacer()
                
                if isCurrentFamily {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
            }
        }
    }
}
