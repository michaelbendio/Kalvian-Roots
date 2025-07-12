//
//  JuuretError.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation

enum JuuretError: Error, LocalizedError {
    case invalidFamilyId(String)
    case fileNotFound
    case extractionFailed(String)
    case foundationModelsUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidFamilyId(let id):
            return "Invalid family ID: \(id). Please check the family ID dictionary."
        case .fileNotFound:
            return "Juuret Kälviällä text file not found in iCloud/Documents/"
        case .extractionFailed(let reason):
            return "Family extraction failed: \(reason)"
        case .foundationModelsUnavailable:
            return "Foundation Models is not available on this device. Please enable Apple Intelligence in System Settings."
        }
    }
}
