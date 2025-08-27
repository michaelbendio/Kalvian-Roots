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
 * Includes AI service errors,  cross-reference resolution errors  and Foundation Models Framework errors.
 */

enum JuuretError: LocalizedError {
    case invalidFamilyId(String)
    case extractionFailed(String)
    case foundationModelsUnavailable  // Keep for legacy compatibility
    
    // MARK: - AI Architecture Errors
    case aiServiceNotConfigured(String)
    case noCurrentFamily
    case crossReferenceFailed(String)
    case fileManagement(String)
    case parsingFailed(String)
    case networkError(String)
    case noFileLoaded
    case familyNotFound(String)
    
    // MARK: - Cross-Reference Resolution Errors
    case noFileContent
    case personNotFound(String)
    case multipleMatches(String)

    var errorDescription: String? {
        switch self {
        case .invalidFamilyId(let familyId):
            return "Invalid family ID: \(familyId)"
        case .extractionFailed(let details):
            return "Family extraction failed: \(details)"
        case .foundationModelsUnavailable:
            return "Foundation Models Framework not available"
            
        // AI architecture errors
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
        case .noFileLoaded:
            return "No file loaded. Please open JuuretKälviällä.txt"
        case .familyNotFound(let familyId):
            return "Family \(familyId) not found in file"
            
        // Cross-reference resolution errors
        case .noFileContent:
            return "No file content available for cross-reference resolution"
        case .personNotFound(let name):
            return "Person not found: \(name)"
        case .multipleMatches(let details):
            return "Multiple matches found, need more criteria: \(details)"
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
        // NEW: Cross-reference resolution recovery suggestions
        case .noFileContent:
            return "Load a genealogical text file before attempting cross-reference resolution."
        case .personNotFound:
            return "Verify the person's name and try again with different spelling variants."
        case .multipleMatches:
            return "Provide additional criteria such as birth date or spouse name to narrow the search."
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
        // NEW: Cross-reference resolution failure reasons
        case .noFileContent:
            return "No genealogical text content available for searching."
        case .personNotFound(let name):
            return "Person '\(name)' could not be located in the genealogical records."
        case .multipleMatches(let details):
            return "Multiple potential matches found: \(details)"
        default:
            return nil
        }
    }
}
