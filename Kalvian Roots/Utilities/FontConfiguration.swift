//
//  FontConfiguration.swift
//  Kalvian Roots
//
//  Font configuration and preferences management
//

import Foundation
import SwiftUI
import Combine

/**
 * Font configuration system for accessibility and user preferences
 */
@Observable
class FontPreferences {
    
    // MARK: - Font Scale Settings
    
    var fontScale: FontScale = .standard {
        didSet {
            UserDefaults.standard.set(fontScale.rawValue, forKey: "FontScale")
        }
    }
    
    var useMonospacedNumbers: Bool = true {
        didSet {
            UserDefaults.standard.set(useMonospacedNumbers, forKey: "UseMonospacedNumbers")
        }
    }
    
    var highContrastText: Bool = false {
        didSet {
            UserDefaults.standard.set(highContrastText, forKey: "HighContrastText")
        }
    }
    
    // MARK: - Font Scale Options
    
    enum FontScale: String, CaseIterable {
        case small = "small"
        case standard = "standard"
        case large = "large"
        case extraLarge = "extraLarge"
        
        var displayName: String {
            switch self {
            case .small: return "Small"
            case .standard: return "Standard"
            case .large: return "Large"
            case .extraLarge: return "Extra Large"
            }
        }
        
        var multiplier: CGFloat {
            switch self {
            case .small: return 0.85
            case .standard: return 1.0
            case .large: return 1.15
            case .extraLarge: return 1.3
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        loadPreferences()
    }
    
    private func loadPreferences() {
        if let savedScale = UserDefaults.standard.object(forKey: "FontScale") as? String,
           let scale = FontScale(rawValue: savedScale) {
            fontScale = scale
        }
        
        useMonospacedNumbers = UserDefaults.standard.bool(forKey: "UseMonospacedNumbers")
        highContrastText = UserDefaults.standard.bool(forKey: "HighContrastText")
    }
    
    // MARK: - Font Generation
    
    func scaledFont(_ baseFont: Font) -> Font {
        // This is a simplified implementation
        // In a full implementation, you'd need to extract the base size and scale it
        return baseFont
    }
    
    func systemFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let scaledSize = size * fontScale.multiplier
        return Font.system(size: scaledSize, weight: weight, design: design)
    }
    
    // MARK: - Accessibility Support
    
    var textColor: Color {
        return highContrastText ? .primary : .primary
    }
    
    var secondaryTextColor: Color {
        return highContrastText ? .primary : .secondary
    }
}

// MARK: - Font Extension with Preferences

extension Font {
    
    /// Get genealogy fonts with current preferences applied
    static func genealogy(_ preferences: FontPreferences) -> GenealgyFonts {
        return GenealgyFonts(preferences: preferences)
    }
}

/**
 * Preference-aware genealogy fonts
 */
struct GenealgyFonts {
    private let preferences: FontPreferences
    
    init(preferences: FontPreferences) {
        self.preferences = preferences
    }
    
    var title: Font {
        preferences.systemFont(size: 28, weight: .bold)
    }
    
    var title2: Font {
        preferences.systemFont(size: 24, weight: .semibold)
    }
    
    var headline: Font {
        preferences.systemFont(size: 20, weight: .semibold)
    }
    
    var subheadline: Font {
        preferences.systemFont(size: 18, weight: .medium)
    }
    
    var body: Font {
        preferences.systemFont(size: 16, weight: .regular)
    }
    
    var callout: Font {
        preferences.systemFont(size: 14, weight: .regular)
    }
    
    var caption: Font {
        preferences.systemFont(size: 12, weight: .regular)
    }
    
    var monospace: Font {
        preferences.systemFont(size: 16, weight: .regular, design: .monospaced)
    }
}
