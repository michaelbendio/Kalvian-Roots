//
//  RootsExtractionService.swift
//  KalvianRootsServer
//
//  Created by Michael Bendio on 11/21/25.
//

import Vapor
import Foundation

/// What we’ll stash into JobState.resultJSON for now.
struct RootsExtractionResult: Content {
    let familyCountEstimate: Int
    let totalLines: Int
    let sample: String
}

struct RootsExtractionService {
    let app: Application

    func runExtraction() async throws -> RootsExtractionResult {
        // Ensure ROOTS_FILE is configured
        guard let rootsEnv = app.roots else {
            throw Abort(.internalServerError, reason: "ROOTS_FILE is not configured on the server.")
        }

        let path = rootsEnv.rootsPath
        let url = URL(fileURLWithPath: path)

        // Load the file (first pass: blocking I/O is fine)
        let data = try Data(contentsOf: url)

        guard let text = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Roots file is not valid UTF-8.")
        }

        // Basic line splitting
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        // VERY naive “family count” guess:
        // count blocks of non-empty lines separated by blank lines.
        var familyCount = 0
        var inBlock = false

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                inBlock = false
            } else if !inBlock {
                inBlock = true
                familyCount += 1
            }
        }

        // Keep a small sample of the file (e.g. for debugging)
        let sample = String(text.prefix(2000))

        return RootsExtractionResult(
            familyCountEstimate: familyCount,
            totalLines: lines.count,
            sample: sample
        )
    }
}
