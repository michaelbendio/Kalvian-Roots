//
//  ClanBrowserView.swift
//  Kalvian Roots
//
//  Dropdown browser for navigating between family clans
//

import SwiftUI

struct ClanBrowserView: View {
    @Environment(JuuretApp.self) private var juuretApp
    @Binding var isPresented: Bool
    
    private let clans: [(clanName: String, suffixes: [String])]
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        
        print("🔍 ClanBrowserView init called")
        print("   FamilyIDs.validFamilyIds.count = \(FamilyIDs.validFamilyIds.count)")
        print("   First 3 IDs: \(FamilyIDs.validFamilyIds.prefix(3))")
        
        let result = Self.groupFamilyIDsByClan()
        print("   Grouped into \(result.count) clans")
        
        if result.isEmpty {
            print("   ❌ ERROR: groupFamilyIDsByClan returned empty!")
        } else {
            print("   ✅ First clan: \(result[0].clanName) with \(result[0].suffixes.count) suffixes")
            print("      Suffixes: \(result[0].suffixes.prefix(5))")
        }
        
        self.clans = result
    }
    
    var body: some View {
        #if os(macOS)
        // macOS version - simpler, no NavigationView needed in sheet
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Family Lines")
                    .font(.headline)
                    .padding()
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .padding()
            }
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            if clans.isEmpty {
                Text("No clans found")
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(clans, id: \.clanName) { clan in
                            clanGroupView(clan: clan)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        #else
        // iOS version - with NavigationView
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(clans, id: \.clanName) { clan in
                        clanGroupView(clan: clan)
                    }
                }
            }
            .navigationTitle("Family Lines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
        #endif
    }
    
    // MARK: - Views
    
    private func clanGroupView(clan: (clanName: String, suffixes: [String])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Clan name header
            Text(clan.clanName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            
            // Suffix buttons
            FlowLayout(spacing: 4) {
                ForEach(clan.suffixes, id: \.self) { suffix in
                    suffixButton(clanName: clan.clanName, suffix: suffix)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
#if os(macOS)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
#else
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator)),
            alignment: .bottom
        )
#endif
    }
    
    private func suffixButton(clanName: String, suffix: String) -> some View {
        let familyId = "\(clanName) \(suffix)"
        let isCurrent = familyId == juuretApp.currentFamily?.familyId
        
        return Button(action: {
            // Navigate immediately without updating history
            juuretApp.navigateToFamily(familyId, updateHistory: false)
            isPresented = false
        }) {
            Text(suffix)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundColor(isCurrent ? .white : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isCurrent ? Color.green : secondarySystemFillColor
                )
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isCurrent ? Color.green : separatorColor,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Platform-specific colors
    
    private var secondarySystemFillColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemFill)
        #endif
    }
    
    private var separatorColor: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
    }
    
    // MARK: - Static Helper
    
    /**
     * Group all family IDs by clan name with their suffixes
     *
     * Parses each family ID to extract:
     * - Clan name (everything before the last space)
     * - Suffix (everything after the last space: digits, roman numerals, etc.)
     *
     * Returns sorted list of (clanName, [suffixes])
     */
    /**
     * Group all family IDs by clan name with their suffixes
     *
     * Parses each family ID to extract:
     * - Clan name (everything before the suffix)
     * - Suffix (roman numeral + number, or just number)
     *
     * Returns sorted list of (clanName, [suffixes])
     */
    static func groupFamilyIDsByClan() -> [(clanName: String, suffixes: [String])] {
        var clanMap: [String: [String]] = [:]
        
        // Parse each family ID
        for familyId in FamilyIDs.validFamilyIds {
            let components = familyId.components(separatedBy: " ")
            guard components.count >= 2 else { continue }
            
            // Determine where the suffix starts
            // Suffix can be:
            // - Just a number: "1", "10", "2B"
            // - Roman numeral + number: "II 1", "III 2", "IV 5"
            
            var suffixStartIndex = components.count - 1
            
            // Check if second-to-last component is a roman numeral
            if components.count >= 3 {
                let possibleRoman = components[components.count - 2]
                if ["I", "II", "III", "IV"].contains(possibleRoman) {
                    suffixStartIndex = components.count - 2
                }
            }
            
            // Clan name is everything before the suffix
            let clanName = components[0..<suffixStartIndex].joined(separator: " ")
            
            // Suffix is everything from suffixStartIndex onward
            let suffix = components[suffixStartIndex...].joined(separator: " ")
            
            // Add to map
            if clanMap[clanName] == nil {
                clanMap[clanName] = []
            }
            clanMap[clanName]?.append(suffix)
        }
        
        // Preserve the order from FamilyIDs.validFamilyIds (file order)
        // Build list of clans in the order they first appear
        var clanOrder: [String] = []
        var seenClans: Set<String> = []

        for familyId in FamilyIDs.validFamilyIds {
            let components = familyId.components(separatedBy: " ")
            guard components.count >= 2 else { continue }
            
            var suffixStartIndex = components.count - 1
            if components.count >= 3 {
                let possibleRoman = components[components.count - 2]
                if ["I", "II", "III", "IV"].contains(possibleRoman) {
                    suffixStartIndex = components.count - 2
                }
            }
            
            let clanName = components[0..<suffixStartIndex].joined(separator: " ")
            
            if !seenClans.contains(clanName) {
                clanOrder.append(clanName)
                seenClans.insert(clanName)
            }
        }

        // Return clans in file order with naturally sorted suffixes
        return clanOrder.map { clanName in
            let suffixes = clanMap[clanName]!.sorted { lhs, rhs in
                return naturalCompare(lhs, rhs)
            }
            return (clanName: clanName, suffixes: suffixes)
        }
    }
    
    /**
     * Natural sort comparison for suffixes
     *
     * Handles:
     * - Plain numbers: 1, 2, 3, ..., 10, 11, 12
     * - Roman numerals: I, II, III, IV
     * - Combined: II 1, II 2, III 1, etc.
     */
    private static func naturalCompare(_ lhs: String, _ rhs: String) -> Bool {
        // Try to parse as integers first
        if let lhsInt = Int(lhs), let rhsInt = Int(rhs) {
            return lhsInt < rhsInt
        }
        
        // Handle roman numeral prefixes (I, II, III, IV)
        let romanValues = ["I": 1, "II": 2, "III": 3, "IV": 4]
        
        let lhsComponents = lhs.components(separatedBy: " ")
        let rhsComponents = rhs.components(separatedBy: " ")
        
        // If both have roman numeral prefixes
        if lhsComponents.count == 2, rhsComponents.count == 2,
           let lhsRoman = romanValues[lhsComponents[0]],
           let rhsRoman = romanValues[rhsComponents[0]] {
            
            if lhsRoman != rhsRoman {
                return lhsRoman < rhsRoman
            }
            
            // Same roman numeral, compare the numeric suffix
            if let lhsNum = Int(lhsComponents[1]), let rhsNum = Int(rhsComponents[1]) {
                return lhsNum < rhsNum
            }
        }
        
        // One has roman numeral, other doesn't - roman numerals come after plain numbers
        if lhsComponents.count == 1 && rhsComponents.count == 2 {
            return true  // lhs (plain) comes before rhs (roman)
        }
        if lhsComponents.count == 2 && rhsComponents.count == 1 {
            return false  // rhs (plain) comes before lhs (roman)
        }
        
        // Fallback to string comparison
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}

// MARK: - Flow Layout

/**
 * Flow layout that wraps items horizontally
 */
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    ClanBrowserView(isPresented: .constant(true))
        .environment(JuuretApp())
}

