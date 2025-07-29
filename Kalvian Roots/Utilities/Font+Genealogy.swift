//
//  Font+Genealogy.swift
//  Kalvian Roots
//
//  Enhanced font system for better genealogical app readability
//
//  Created by Michael Bendio on 7/26/25.
//

import SwiftUI

/**
 * Enhanced font sizes for genealogical research
 * Optimized for readability with historical documents and data entry
 */
extension Font {
    
    // MARK: - Primary Typography Scale
    
    /// Large title for main headings
    static let genealogyTitle = Font.system(size: 28, weight: .bold, design: .default)
    
    /// Secondary title for section headers
    static let genealogyTitle2 = Font.system(size: 24, weight: .semibold, design: .default)
    
    /// Headline for family names and important info
    static let genealogyHeadline = Font.system(size: 20, weight: .semibold, design: .default)
    
    /// Subheadline for person names and dates
    static let genealogySubheadline = Font.system(size: 18, weight: .medium, design: .default)
    
    /// Body text for general content
    static let genealogyBody = Font.system(size: 16, weight: .regular, design: .default)
    
    /// Callout for secondary information
    static let genealogyCallout = Font.system(size: 14, weight: .regular, design: .default)
    
    /// Caption for metadata and notes
    static let genealogyCaption = Font.system(size: 12, weight: .regular, design: .default)
    
    /// Small caption for fine details
    static let genealogyCaption2 = Font.system(size: 10, weight: .regular, design: .default)
    
    // MARK: - Specialized Typography
    
    /// Monospaced fonts for dates, IDs, and technical data
    static let genealogyMonospace = Font.system(size: 16, weight: .regular, design: .monospaced)
    
    /// Small monospaced for compact technical data
    static let genealogyMonospaceSmall = Font.system(size: 14, weight: .regular, design: .monospaced)
    
    /// Large monospaced for prominent IDs and references
    static let genealogyMonospaceLarge = Font.system(size: 18, weight: .medium, design: .monospaced)
    
    // MARK: - Interactive Elements
    
    /// Button text with appropriate weight
    static let genealogyButton = Font.system(size: 16, weight: .medium, design: .default)
    
    /// Small button text
    static let genealogyButtonSmall = Font.system(size: 14, weight: .medium, design: .default)
    
    /// Link text with subtle emphasis
    static let genealogyLink = Font.system(size: 16, weight: .regular, design: .default)
}
