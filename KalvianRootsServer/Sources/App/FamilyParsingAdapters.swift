import Foundation
import KalvianRootsCore
import Vapor

/// Minimal parser that extracts a nuclear family from the Juuret Kälviällä text format.
/// This is intentionally lightweight but returns full KalvianRootsCore models
/// so the server can use the shared citation generator.
struct SimpleFamilyParser: FamilyParsingService {
    let logger: Logger

    func parseFamily(familyId: String, familyText: String) async throws -> Family {
        let lines = familyText.split(separator: "\n", omittingEmptySubsequences: false)
        let header = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? familyId
        let pageReferences = extractPageReferences(from: header)

        var people: [ParsedPerson] = []
        let nameRegex = try NSRegularExpression(
            pattern: "\\b[\\p{Lu}][\\p{Ll}]+(?:\\s+[\\p{Lu}][\\p{Ll}]+)+",
            options: [.caseInsensitive]
        )

        for (index, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = nameRegex.matches(in: String(line), range: range)
            guard let match = matches.first else { continue }

            let name = nsLine.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            let birth = extractBirth(from: String(line))
            let role: ParsedPerson.Role = index <= 2 ? .parent : .child
            people.append(ParsedPerson(name: name, birth: birth, role: role, line: String(line)))
        }

        let family = makeFamily(
            id: familyId,
            pageReferences: pageReferences,
            parsedPeople: people
        )

        logger.debug("[Parser] Parsed family \(family.familyId) with \(family.allParents.count) parents and \(family.allChildren.count) children")

        return family
    }

    private func extractPageReferences(from header: String) -> [String] {
        let pattern = "\\b\\d{1,4}\\b"
        let matches = header.matches(for: pattern)
        return matches.isEmpty ? ["?"] : matches
    }

    private func extractBirth(from line: String) -> String? {
        if let starRange = line.range(of: "★\\s*([^\\s]+)", options: .regularExpression) {
            return String(line[starRange]).replacingOccurrences(of: "★", with: "").trimmingCharacters(in: .whitespaces)
        }

        if let dateRange = line.range(of: "\\b\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}\\b", options: .regularExpression) {
            return String(line[dateRange])
        }

        if let yearRange = line.range(of: "\\b\\d{4}\\b", options: .regularExpression) {
            return String(line[yearRange])
        }

        return nil
    }

    private func makeFamily(id: String, pageReferences: [String], parsedPeople: [ParsedPerson]) -> Family {
        // Map parsed people into core models
        let parents = parsedPeople.filter { $0.role == .parent }
        let children = parsedPeople.filter { $0.role == .child }

        let husbandPerson = parents.first.map { person(from: $0) } ?? Person(name: "")
        let wifePerson = parents.count > 1 ? person(from: parents[1]) : Person(name: "")
        let childPersons = children.map { person(from: $0) }

        let couple = Couple(
            husband: husbandPerson,
            wife: wifePerson,
            children: childPersons
        )

        return Family(
            familyId: id,
            pageReferences: pageReferences,
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }

    private func person(from parsed: ParsedPerson) -> Person {
        Person(
            name: parsed.name,
            birthDate: parsed.birth,
            noteMarkers: []
        )
    }
}

/// Parsed person used by the simple parser.
struct ParsedPerson: Equatable {
    enum Role { case parent, child }

    let name: String
    let birth: String?
    let role: Role
    let line: String
}

private extension String {
    func matches(for pattern: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..<endIndex, in: self)
            let matches = regex.matches(in: self, range: nsRange)
            return matches.compactMap { Range($0.range, in: self).map { String(self[$0]) } }
        } catch {
            return []
        }
    }
}

/// Minimal file manager that knows how to extract family blocks from the ROOTS_FILE.
struct RootsFileManager: FamilyFileManaging {
    let rootsPath: String
    let logger: Logger

    func extractFamilyText(familyId: String) -> String? {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: rootsPath)),
            let text = String(data: data, encoding: .utf8)
        else {
            logger.error("[RootsFileManager] Unable to load ROOTS file at \(rootsPath)")
            return nil
        }

        let lowercasedNeedle = familyId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var block: [Substring] = []

        func checkCurrentBlock() -> String? {
            guard let header = block.first?.trimmingCharacters(in: .whitespaces) else { return nil }
            if header.lowercased().hasPrefix(lowercasedNeedle) {
                return block.joined(separator: "\n")
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

        return checkCurrentBlock()
    }

    func findNextFamilyId(after familyId: String) -> String? { nil }

    func getAllFamilyIds() -> [String] { [] }
}

/// Fallback file manager used when ROOTS_FILE is not configured.
struct NullRootsFileManager: FamilyFileManaging {
    func extractFamilyText(familyId: String) -> String? { nil }
    func findNextFamilyId(after familyId: String) -> String? { nil }
    func getAllFamilyIds() -> [String] { [] }
}
