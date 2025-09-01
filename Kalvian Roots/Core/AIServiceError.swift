//
//  AIServiceError.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 8/31/25.
//

//
//  AIServiceError.swift
//  Kalvian Roots
//
//  Complete error definitions for AI services
//

import Foundation

// MARK: - AI Service Errors

enum AIServiceError: LocalizedError {
    case notConfigured(String)
    case unknownService(String)
    case invalidResponse(String)
    case networkError(Error)
    case parsingFailed(String)
    case rateLimited
    case apiKeyMissing
    case httpError(Int, String)
    case apiError(String)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured(let service):
            return "\(service) is not configured. Please add API key in settings."
        case .unknownService(let name):
            return "Unknown AI service: \(name)"
        case .invalidResponse(let details):
            return "Invalid response: \(details)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingFailed(let details):
            return "Failed to parse response: \(details)"
        case .rateLimited:
            return "AI service rate limit reached. Please try again later."
        case .apiKeyMissing:
            return "API key is required"
        case .httpError(let code, let message):
            return "HTTP Error \(code): \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
}
