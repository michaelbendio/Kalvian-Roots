//
//  CachedFamiliesMenu.swift
//  Kalvian Roots
//
//  Cache management with popover-based search capability
//
//  Created by Michael Bendio on 9/23/25.
//

import SwiftUI

struct CachedFamiliesMenu: View {
    @Environment(JuuretApp.self) private var app
    @State private var searchText = ""
    @State private var showingPopover = false
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
    
    // Limit display to prevent list from becoming too long
    var displayedFamilyIds: ArraySlice<String> {
        filteredFamilyIds.prefix(20)  // Show max 20 at a time
    }
    
    var hasMore: Bool {
        filteredFamilyIds.count > 20
    }
    
    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Label("Cached Families (\(allCachedFamilyIds.count))", systemImage: "internaldrive")
        }
        .popover(isPresented: $showingPopover) {
            cachedFamiliesContent
                .frame(width: 400, height: 550)
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
    
    // MARK: - Popover Content
    
    private var cachedFamiliesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Cached Families")
                    .font(.headline)
                Spacer()
                Button {
                    showingPopover = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if allCachedFamilyIds.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No cached families")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Families will be cached as you extract them")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack(spacing: 0) {
                    // Search field (only show if more than 5 families)
                    if allCachedFamilyIds.count > 5 {
                        SearchFieldView(text: $searchText)
                            .padding(.horizontal)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                    }
                    
                    Divider()
                    
                    // Scrollable family list
                    ScrollView {
                        if filteredFamilyIds.isEmpty && !searchText.isEmpty {
                            // No search results
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                Text("No families matching '\(searchText)'")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            // Family list
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(displayedFamilyIds), id: \.self) { familyId in
                                    FamilyRow(
                                        familyId: familyId,
                                        isCurrentFamily: app.currentFamily?.familyId == familyId,
                                        onLoad: {
                                            showingPopover = false
                                            Task {
                                                await app.extractFamily(familyId: familyId)
                                            }
                                        },
                                        onRegenerate: {
                                            showingPopover = false
                                            Task {
                                                await app.regenerateCachedFamily(familyId: familyId)
                                            }
                                        },
                                        onDelete: {
                                            familyToDelete = familyId
                                            showingDeleteConfirmation = true
                                        }
                                    )
                                    
                                    Divider()
                                }
                                
                                // Show count if more results available
                                if hasMore {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("+ \(filteredFamilyIds.count - 20) more families")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Refine search to see more")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Footer with cache info and actions
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                        Text("\(allCachedFamilyIds.count) families cached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            showingClearAllConfirmation = true
                        } label: {
                            Label("Clear All", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Search Field Component

/// Search field that properly works in a popover (unlike in menus)
private struct SearchFieldView: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
            
            TextField("Search family ID...", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
            
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            // Auto-focus works properly in popovers!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isFocused = true
            }
        }
    }
}

// MARK: - Family Row Component

/// Individual family row with actions menu
private struct FamilyRow: View {
    let familyId: String
    let isCurrentFamily: Bool
    let onLoad: () -> Void
    let onRegenerate: () -> Void
    let onDelete: () -> Void
    
    @Environment(JuuretApp.self) private var app
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Main button to load family
            Button {
                onLoad()
            } label: {
                HStack {
                    Text(familyId)
                        .fontWeight(isCurrentFamily ? .semibold : .regular)
                        .foregroundStyle(isCurrentFamily ? .primary : .primary)
                    
                    Spacer()
                    
                    if isCurrentFamily {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .imageScale(.small)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Actions menu
            Menu {
                Button {
                    onLoad()
                } label: {
                    Label("Load Family", systemImage: "doc.text")
                }
                
                Button {
                    onRegenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete from Cache", systemImage: "trash")
                }
                
                // Show cache metadata
                if let info = app.familyNetworkCache.getCachedFamilyInfo(familyId: familyId) {
                    Divider()
                    
                    Text("Cached: \(info.cachedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                    
                    Text("Extraction: \(String(format: "%.1f", info.extractionTime))s")
                        .font(.caption)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .imageScale(.medium)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24, height: 24)
            .help("Family actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
