//
//  JuuretError.swift
//  Kalvian Roots
//
//  Updated error types for AI parsing architecture
//

import Foundation

/**
 * JuuretError.swift - Comprehensive error types for genealogical app
 *
 * Updated to include AI service errors and cross-reference resolution errors
 * alongside existing Foundation Models Framework errors.
 */

enum JuuretError: LocalizedError {
    // MARK: - Existing Errors (preserve compatibility)
    case invalidFamilyId(String)
    case extractionFailed(String)
    case foundationModelsUnavailable  // Keep for legacy compatibility
    
    // MARK: - New AI Architecture Errors
    case aiServiceNotConfigured(String)
    case noCurrentFamily
    case crossReferenceFailed(String)
    case fileManagement(String)
    case parsingFailed(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        // Existing errors
        case .invalidFamilyId(let familyId):
            return "Invalid family ID: \(familyId)"
        case .extractionFailed(let details):
            return "Family extraction failed: \(details)"
        case .foundationModelsUnavailable:
            return "Foundation Models Framework not available"
            
        // New AI architecture errors
        case .aiServiceNotConfigured(let serviceName):
            return "\(serviceName) not configured. Please add API key in settings."
        case .noCurrentFamily:
            return "No family currently loaded"
        case .crossReferenceFailed(let details):
            return "Cross-reference resolution failed: \(details)"
        case .fileManagement(let details):
            return "File management error: \(details)"
        case .parsingFailed(let details):
            return "AI parsing failed: \(details)"
        case .networkError(let details):
            return "Network error: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidFamilyId:
            return "Please check the family ID spelling and try again."
        case .aiServiceNotConfigured:
            return "Configure an AI service API key in the app settings."
        case .noCurrentFamily:
            return "Extract a family first before attempting this operation."
        case .crossReferenceFailed:
            return "Try extracting the family again or check the source file."
        case .fileManagement:
            return "Check file permissions and try reopening the file."
        case .parsingFailed:
            return "Try switching to a different AI service or check your internet connection."
        case .networkError:
            return "Check your internet connection and try again."
        default:
            return nil
        }
    }
    
    var failureReason: String? {
        switch self {
        case .invalidFamilyId(let familyId):
            return "The family ID '\(familyId)' is not found in the valid family IDs list."
        case .aiServiceNotConfigured(let serviceName):
            return "The \(serviceName) service requires an API key to function."
        case .noCurrentFamily:
            return "No family data is currently loaded in the application."
        case .crossReferenceFailed:
            return "Unable to resolve family cross-references from the source text."
        case .fileManagement:
            return "File system operation failed."
        case .parsingFailed:
            return "AI service returned invalid or unparseable response."
        case .networkError:
            return "Network communication with AI service failed."
        default:
            return nil
        }
    }
}
