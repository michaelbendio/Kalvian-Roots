import Foundation
import Vapor

struct RootsFamilyLookupService {
    let app: Application

    struct FamilyResponse: Content {
        let id: String
        let text: String
    }

    func findFamily(id: String) async throws -> FamilyResponse {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw Abort(.badRequest, reason: "Family ID is required.")
        }

        guard let rootsEnv = app.roots else {
            throw Abort(.internalServerError, reason: "ROOTS_FILE is not configured on the server.")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: rootsEnv.rootsPath))
        guard let text = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Roots file is not valid UTF-8.")
        }

        let lowercasedNeedle = trimmedID.lowercased()
        var block: [Substring] = []

        func checkCurrentBlock() -> FamilyResponse? {
            guard let header = block.first?.trimmingCharacters(in: .whitespaces) else { return nil }
            if header.lowercased().hasPrefix(lowercasedNeedle) {
                let blockText = block.joined(separator: "\n")
                return FamilyResponse(id: trimmedID, text: blockText)
            }
            return nil
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if let match = checkCurrentBlock() {
                    return match
                }
                block.removeAll(keepingCapacity: true)
            } else {
                block.append(line)
            }
        }

        if let match = checkCurrentBlock() {
            return match
        }

        throw Abort(.notFound, reason: "Family \(trimmedID) not found.")
    }
}
