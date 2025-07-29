//
//  ExtractionProgress.swift
//  Kalvian Roots
//
//  Progress tracking for family extraction workflow
//
//  Created by Michael Bendio on 7/28/25.
//

import Foundation

/**
 * Extraction progress tracking for family processing workflow
 */
enum ExtractionProgress {
    case idle
    case extractingFamily
    case familyExtracted
    case resolvingCrossReferences
    case crossReferencesResolved
    case complete
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .extractingFamily:
            return "Extracting family..."
        case .familyExtracted:
            return "Family extracted"
        case .resolvingCrossReferences:
            return "Resolving cross-references..."
        case .crossReferencesResolved:
            return "Cross-references resolved"
        case .complete:
            return "Complete - ready for citations"
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .extractingFamily, .resolvingCrossReferences:
            return true
        default:
            return false
        }
    }
}
