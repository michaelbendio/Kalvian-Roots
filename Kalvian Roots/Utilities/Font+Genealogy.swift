//
//  Font+Genealogy.swift
//  Kalvian Roots
//
//  Enhanced font system for better genealogical app readability
//
//  Created by Michael Bendio on 7/26/25.
//

import SwiftUI

// MARK: - Font Extensions for Genealogy Views

extension Font {
    /// Large title font for main headings
    static let genealogyTitle = Font.system(size: 24, weight: .bold)
    
    /// Headline font for section headers
    static let genealogyHeadline = Font.system(size: 20, weight: .semibold)
    
    /// Subheadline font for subsection headers
    static let genealogySubheadline = Font.system(size: 18)
    
    /// Body font for main content
    static let genealogyBody = Font.system(size: 16)
    
    /// Callout font for secondary content
    static let genealogyCallout = Font.system(size: 15)
    
    /// Caption font for labels and small text
    static let genealogyCaption = Font.system(size: 14)
    
    /// Small monospaced font for code, IDs, and technical content
    static let genealogyMonospaceSmall = Font.system(size: 13, design: .monospaced)
}
