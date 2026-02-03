//
//  HiskiQueryResult.swift
//  Kalvian Roots
//
//  Domain-level abstraction for HisKi query results
//  Used by both SwiftUI app and HTTP server
//

import Foundation

/**
 * Result type for HisKi queries providing clean abstraction
 * between the query logic and UI/server presentation layer
 */
enum HiskiQueryResult {
    /// Found a single matching record with citation URL
    case found(citationURL: String, recordURL: String? = nil)

    /// No matching record found
    case notFound

    /// Multiple matching records found, requires manual selection
    case multipleResults(searchURL: String)

    /// Query failed with error message
    case error(message: String)

    /// Convenience computed property for success check
    var isSuccess: Bool {
        switch self {
        case .found:
            return true
        default:
            return false
        }
    }

    /// Extract citation URL if found
    var citationURL: String? {
        switch self {
        case .found(let citationURL, _):
            return citationURL
        default:
            return nil
        }
    }
    
    /// Extract record URL for browser viewing
    var recordURL: String? {
        switch self {
        case .found(_, let url):
            return url
        default:
            return nil
        }
    }

    /// Extract search URL for multiple results
    var searchURL: String? {
        switch self {
        case .multipleResults(let url):
            return url
        default:
            return nil
        }
    }

    /// Extract error message if failed
    var errorMessage: String? {
        switch self {
        case .error(let message):
            return message
        default:
            return nil
        }
    }
}
