//
//  FontConfiguration.swift
//  Kalvian Roots
//
//  Centralized font configuration for larger, more readable interface
//
//  Created by Michael Bendio on 7/26/25.
//

import SwiftUI

/**
 * FontConfiguration.swift - Centralized font sizing
 *
 * Provides larger, more readable fonts throughout the application.
 * All components should use these standardized font sizes.
 */

extension Font {
    
    // MARK: - Genealogy App Specific Fonts (Larger Sizes)
    
    /// Large title for main screens (28pt)
    static let genealogyTitle = Font.system(size: 28, weight: .bold, design: .default)
    
    /// Section headers (22pt)
    static let genealogyHeadline = Font.system(size: 22, weight: .semibold, design: .default)
    
    /// Sub-section headers (18pt)
    static let genealogySubheadline = Font.system(size: 18, weight: .medium, design: .default)
    
    /// Body text - primary content (16pt)
    static let genealogyBody = Font.system(size: 16, weight: .regular, design: .default)
    
    /// Body text - emphasized (16pt medium)
    static let genealogyBodyEmphasized = Font.system(size: 16, weight: .medium, design: .default)
    
    /// Secondary text (14pt)
    static let genealogyCaption = Font.system(size: 14, weight: .regular, design: .default)
    
    /// Small labels and notes (12pt)
    static let genealogyFootnote = Font.system(size: 12, weight: .regular, design: .default)
    
    /// Monospaced text for code/data (16pt)
    static let genealogyMono = Font.system(size: 16, weight: .regular, design: .monospaced)
    
    /// Small monospaced text (14pt)
    static let genealogyMonoSmall = Font.system(size: 14, weight: .regular, design: .monospaced)
    
    // MARK: - Platform-Specific Adjustments
    
    /// Dynamic body font that adjusts per platform
    static var platformBody: Font {
        #if os(macOS)
        return .genealogyBody
        #elseif os(iOS)
        return .system(size: 18, weight: .regular) // Slightly larger on mobile
        #else
        return .genealogyBody
        #endif
    }
    
    /// Dynamic caption font that adjusts per platform
    static var platformCaption: Font {
        #if os(macOS)
        return .genealogyCaption
        #elseif os(iOS)
        return .system(size: 16, weight: .regular) // Larger on mobile
        #else
        return .genealogyCaption
        #endif
    }
}

// MARK: - View Modifier for Consistent Font Application

/**
 * Convenient view modifier for applying genealogy fonts
 */
struct GenealogyFontModifier: ViewModifier {
    let fontType: GenealogyFontType
    
    func body(content: Content) -> some View {
        content.font(fontType.font)
    }
}

enum GenealogyFontType {
    case title
    case headline
    case subheadline
    case body
    case bodyEmphasized
    case caption
    case footnote
    case mono
    case monoSmall
    case platformBody
    case platformCaption
    
    var font: Font {
        switch self {
        case .title: return .genealogyTitle
        case .headline: return .genealogyHeadline
        case .subheadline: return .genealogySubheadline
        case .body: return .genealogyBody
        case .bodyEmphasized: return .genealogyBodyEmphasized
        case .caption: return .genealogyCaption
        case .footnote: return .genealogyFootnote
        case .mono: return .genealogyMono
        case .monoSmall: return .genealogyMonoSmall
        case .platformBody: return .platformBody
        case .platformCaption: return .platformCaption
        }
    }
}

extension View {
    /// Apply a genealogy font type to this view
    func genealogyFont(_ fontType: GenealogyFontType) -> some View {
        self.modifier(GenealogyFontModifier(fontType: fontType))
    }
}

// MARK: - Text Size Preferences

/**
 * User preference for text size scaling
 */
class FontPreferences: ObservableObject {
    @Published var textSizeMultiplier: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(textSizeMultiplier, forKey: "TextSizeMultiplier")
        }
    }
    
    init() {
        self.textSizeMultiplier = UserDefaults.standard.double(forKey: "TextSizeMultiplier")
        if textSizeMultiplier == 0 { textSizeMultiplier = 1.0 } // Default value
    }
    
    /// Apply user scaling to a font size
    func scaledSize(_ baseSize: CGFloat) -> CGFloat {
        return baseSize * textSizeMultiplier
    }
}

// MARK: - Accessibility Support

extension Font {
    /// Create a font that respects both our sizing and accessibility settings
    static func genealogyAccessible(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Usage Examples and Guidelines

/**
 * Usage Guidelines:
 *
 * 1. Main titles: .genealogyFont(.title)
 * 2. Section headers: .genealogyFont(.headline)
 * 3. Regular content: .genealogyFont(.body) or .genealogyFont(.platformBody)
 * 4. Secondary info: .genealogyFont(.caption) or .genealogyFont(.platformCaption)
 * 5. API keys, code: .genealogyFont(.mono)
 *
 * Example:
 * Text("Family Information")
 *     .genealogyFont(.headline)
 *
 * Text("Matti Erikinp., b 9 September 1727")
 *     .genealogyFont(.platformBody)
 */
