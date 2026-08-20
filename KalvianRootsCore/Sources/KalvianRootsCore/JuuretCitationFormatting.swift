import Foundation

/// Shared deterministic display rules used by both the app and MCP citation paths.
public enum JuuretCitationFormatting {
  public static func date(_ raw: String, parentBirthYear: Int? = nil) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("n ") {
      return "abt \(value.dropFirst(2).trimmingCharacters(in: .whitespaces))"
    }
    if value.hasPrefix("n"), let year = Int(value.dropFirst()) {
      return "abt \(year)"
    }

    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let day = Int(parts[0]),
      let month = Int(parts[1]),
      (1...12).contains(month)
    else { return value }

    let year: Int
    if parts[2].count == 4, let parsed = Int(parts[2]) {
      year = parsed
    } else if parts[2].count == 2, let parsed = Int(parts[2]) {
      year = inferCentury(for: parsed, parentBirthYear: parentBirthYear)
    } else {
      return value
    }
    let months = [
      "January", "February", "March", "April", "May", "June", "July", "August",
      "September", "October", "November", "December",
    ]
    return "\(day) \(months[month - 1]) \(year)"
  }

  public static func marriageDate(_ raw: String, parentBirthYear: Int?) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.contains(".") { return date(value, parentBirthYear: parentBirthYear) }
    if value.count == 2, let year = Int(value) {
      return String(inferCentury(for: year, parentBirthYear: parentBirthYear))
    }
    return value
  }

  public static func inferCentury(for twoDigitYear: Int, parentBirthYear: Int?) -> Int {
    guard let birth = parentBirthYear else { return 1700 + twoDigitYear }
    let candidates = [1600 + twoDigitYear, 1700 + twoDigitYear, 1800 + twoDigitYear]
    if let plausible = candidates.first(where: { (15...50).contains($0 - birth) }) {
      return plausible
    }
    return candidates.min(by: {
      distanceFromMarriageAge($0 - birth) < distanceFromMarriageAge($1 - birth)
    }) ?? 1700 + twoDigitYear
  }

  public static func birthYear(from raw: String?) -> Int? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 3 { return Int(parts[2]) }
    return value.count == 4 ? Int(value) : nil
  }

  public static func footnoteMarker(_ marker: String) -> String {
    marker.map { $0 == "★" ? "*" : String($0) }.joined()
  }

  public static func footnoteText(_ text: String) -> String {
    var markerEnd = text.startIndex
    while markerEnd < text.endIndex {
      let character = text[markerEnd]
      guard character == "★" || character == "*" else { break }
      markerEnd = text.index(after: markerEnd)
    }
    guard markerEnd > text.startIndex else { return text }
    return footnoteMarker(String(text[..<markerEnd])) + String(text[markerEnd...])
  }

  private static func distanceFromMarriageAge(_ age: Int) -> Int {
    age < 15 ? 15 - age : max(0, age - 50)
  }
}
