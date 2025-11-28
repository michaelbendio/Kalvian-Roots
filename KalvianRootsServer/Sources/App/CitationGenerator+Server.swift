import Foundation

struct CitationGenerator {
    static func generateAsChildCitation(for person: ParsedPerson, in family: ParsedFamily) -> String {
        var parts: [String] = []
        parts.append("Citation for \(person.name)")
        if !person.birth.isEmpty { parts.append("b. \(person.birth)") }
        parts.append("(as child in \(family.id))")
        if let parentSummary = parentLines(from: family) {
            parts.append(parentSummary)
        }
        return parts.joined(separator: " ")
    }

    static func generateParentCitation(for person: ParsedPerson, in family: ParsedFamily) -> String {
        var parts: [String] = []
        parts.append("Citation for \(person.name)")
        if !person.birth.isEmpty { parts.append("b. \(person.birth)") }
        parts.append("(parent in \(family.id))")
        if let childSummary = childLines(from: family) {
            parts.append(childSummary)
        }
        return parts.joined(separator: " ")
    }

    private static func parentLines(from family: ParsedFamily) -> String? {
        let parents = family.persons.filter { $0.role == .parent }
        guard !parents.isEmpty else { return nil }
        let formatted = parents.map { parent in
            if parent.birth.isEmpty { return parent.name }
            return "\(parent.name) (b. \(parent.birth))"
        }
        return "Parents: " + formatted.joined(separator: ", ")
    }

    private static func childLines(from family: ParsedFamily) -> String? {
        let children = family.persons.filter { $0.role == .child }
        guard !children.isEmpty else { return nil }
        let formatted = children.prefix(3).map { child in
            if child.birth.isEmpty { return child.name }
            return "\(child.name) (b. \(child.birth))"
        }
        var summary = "Children: " + formatted.joined(separator: ", ")
        if children.count > 3 {
            summary += " (+\(children.count - 3) more)"
        }
        return summary
    }
}
